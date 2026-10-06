import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math';
import 'dart:typed_data';

import 'yubikey_ctaphid.dart';

export 'yubikey_ctaphid.dart' show CtapHidException, padHmacChallenge;

// The YubiKey helpers talk to the key over WebHID (`navigator.hid`). The
// file and `isWebUsbAvailable` names predate that and are kept for callers.

const int _yubiKeyVendorId = 0x1050;

final Uint8List _otpAppletAid = Uint8List.fromList([
  0xA0,
  0x00,
  0x00,
  0x05,
  0x27,
  0x20,
  0x01,
]);

@JS('navigator.hid')
external JSObject? get _navigatorHid;

/// Whether the browser exposes WebHID, which the YubiKey helpers require.
bool get isWebUsbAvailable => _navigatorHid != null;

/// Shows the browser's HID device chooser filtered to YubiKeys.
///
/// Returns `null` when the chooser is dismissed without picking a device.
/// Other failures (for example a `SecurityError` when WebHID is blocked by
/// permissions policy or the call is not triggered by a user gesture) are
/// rethrown so callers can tell the user access was denied.
Future<JSObject?> requestYubiKey() async {
  final hid = _navigatorHid;
  if (hid == null) {
    throw UnsupportedError('WebHID is not available in this browser');
  }

  try {
    // Filter for YubiKey vendor ID. Chrome will show all non-blocked HID
    // collections — the vendor-specific interface (0xFF00) is accessible.
    final filters = [
      {'vendorId': _yubiKeyVendorId}.jsify(),
    ].toJS;
    final options = {'filters': filters}.jsify();

    final devices = await (hid.callMethod<JSPromise<JSAny>>(
      'requestDevice'.toJS,
      options,
    )).toDart;

    final deviceArray = devices as JSArray;
    if (deviceArray.length == 0) return null;
    return deviceArray[0] as JSObject;
  } catch (e) {
    if (_isDomException(e, 'NotFoundError')) return null;
    rethrow;
  }
}

/// Computes the HMAC-SHA1 challenge-response for [challenge] on [slot]
/// (1 or 2) of the YubiKey [device] returned by [requestYubiKey].
///
/// Returns the 20-byte response as lowercase hex.
Future<String> yubikeyChallengeResponse(
  JSObject device,
  Uint8List challenge, {
  int slot = 2,
}) async {
  // Validate before touching the device.
  final hmacApdu = buildHmacChallengeApdu(challenge, slot: slot);

  await (device.callMethod<JSPromise<JSAny?>>('open'.toJS)).toDart;

  try {
    final nonce = _randomBytes(8);

    final initResponse = await _ctapHidExchange(
      device,
      Uint8List.fromList([0xFF, 0xFF, 0xFF, 0xFF]),
      ctapHidInit,
      nonce,
    );

    if (initResponse.length < 12) {
      throw Exception('CTAP INIT response too short: ${initResponse.length}');
    }
    final channelId = Uint8List.fromList(initResponse.sublist(8, 12));

    final selectApdu = Uint8List.fromList([
      0x00, 0xA4, 0x04, 0x00, // CLA INS P1 P2
      _otpAppletAid.length, // Lc
      ..._otpAppletAid, // AID data
    ]);
    final selectResp = await _ctapHidExchange(
      device,
      channelId,
      ctapHidMsg,
      selectApdu,
    );

    if (!_hasStatusOk(selectResp)) {
      throw Exception('OTP applet SELECT failed: ${_hexEncode(selectResp)}');
    }

    final hmacResp = await _ctapHidExchange(
      device,
      channelId,
      ctapHidMsg,
      hmacApdu,
    );

    if (hmacResp.length >= 2 && !_hasStatusOk(hmacResp)) {
      throw Exception(
        'YubiKey rejected the challenge (status '
        '${_hexEncode(hmacResp.sublist(hmacResp.length - 2))}); '
        'is slot $slot configured for HMAC-SHA1 challenge-response?',
      );
    }
    if (hmacResp.length < 22) {
      throw Exception(
        'HMAC response too short (${hmacResp.length}): ${_hexEncode(hmacResp)}',
      );
    }

    final hmacOutput = hmacResp.sublist(0, 20);
    return _hexEncode(hmacOutput);
  } finally {
    try {
      await (device.callMethod<JSPromise<JSAny?>>('close'.toJS)).toDart;
    } catch (_) {}
  }
}

Future<Uint8List> _ctapHidExchange(
  JSObject device,
  Uint8List channelId,
  int command,
  Uint8List payload,
) async {
  final frames = encodeCtapHidFrames(channelId, command, payload);
  final decoder = CtapHidResponseDecoder(channelId, command);
  final completer = Completer<Uint8List>();

  void handleReport(JSObject event) {
    if (completer.isCompleted) return;
    try {
      final view = event.getProperty<JSDataView>('data'.toJS).toDart;
      final bytes =
          view.buffer.asUint8List(view.offsetInBytes, view.lengthInBytes);
      final response = decoder.add(bytes);
      if (response != null) {
        completer.complete(response);
      }
    } catch (e, st) {
      completer.completeError(e, st);
    }
  }

  final jsCallback = handleReport.toJS;
  device.callMethod<JSAny?>(
    'addEventListener'.toJS,
    'inputreport'.toJS,
    jsCallback,
  );

  try {
    for (final frame in frames) {
      await (device.callMethod<JSPromise<JSAny?>>(
        'sendReport'.toJS,
        0.toJS,
        frame.toJS,
      )).toDart;
    }

    return await completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () =>
          throw TimeoutException('YubiKey did not respond within 10 seconds'),
    );
  } finally {
    device.callMethod<JSAny?>(
      'removeEventListener'.toJS,
      'inputreport'.toJS,
      jsCallback,
    );
  }
}

bool _hasStatusOk(Uint8List response) =>
    response.length >= 2 &&
    response[response.length - 2] == 0x90 &&
    response[response.length - 1] == 0x00;

bool _isDomException(Object error, String name) {
  // Rejections from browser APIs arrive as the JS error object under both
  // dart2js and dart2wasm.
  // ignore: invalid_runtime_check_with_js_interop_types
  if (error is! JSObject) return false;
  final errorName = error.getProperty<JSAny?>('name'.toJS);
  return errorName.isA<JSString>() && (errorName as JSString).toDart == name;
}

Uint8List _randomBytes(int length) {
  final rng = Random.secure();
  return Uint8List.fromList(List.generate(length, (_) => rng.nextInt(256)));
}

String _hexEncode(Uint8List bytes) {
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
