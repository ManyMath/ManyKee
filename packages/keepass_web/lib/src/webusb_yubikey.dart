import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

/// WebUSB YubiKey challenge-response for browser-based authentication.
///
/// This module handles the Dart side of WASM-03: YubiKey challenge-response
/// in the browser via WebUSB API. The computed response bytes are passed to
/// the WASM module's `open_db_with_challenge_response` function.
///
/// Usage:
/// 1. Call [requestYubiKey] from a user gesture handler to get device access
/// 2. Call [yubikeyChallengeResponse] with the challenge from the KDBX header
/// 3. Pass the hex response to KeePassWebApi.openDatabaseWithChallengeResponse

/// YubiKey USB vendor ID.
const int _yubiKeyVendorId = 0x1050;

/// YubiKey HID interface number for challenge-response.
const int _yubiKeyInterface = 0;

/// YubiKey HID configuration value.
const int _yubiKeyConfiguration = 1;

/// HID report size for YubiKey.
const int _hidReportSize = 64;

/// Slot 2 challenge-response command byte.
const int _slot2ChallengeCmd = 0x20;

// WebUSB JS interop types
@JS('navigator.usb')
external JSObject? get _navigatorUsb;

/// Check if WebUSB is available in this browser.
bool get isWebUsbAvailable => _navigatorUsb != null;

/// Request access to a YubiKey device via WebUSB.
///
/// MUST be called from a user gesture handler (click, tap).
/// Returns a [JSObject] representing the USBDevice, or null if user cancelled.
///
/// Throws if WebUSB is not available.
Future<JSObject?> requestYubiKey() async {
  final usb = _navigatorUsb;
  if (usb == null) {
    throw UnsupportedError('WebUSB is not available in this browser');
  }

  try {
    final filters = [
      {'vendorId': _yubiKeyVendorId}.jsify(),
    ].toJS;
    final options = {'filters': filters}.jsify();

    final device = await (usb.callMethod<JSPromise<JSObject>>(
      'requestDevice'.toJS,
      options,
    ))
        .toDart;

    return device;
  } catch (e) {
    // User cancelled the device picker or no device found
    return null;
  }
}

/// Perform HMAC-SHA1 challenge-response with a YubiKey via WebUSB.
///
/// [device] is a USBDevice obtained from [requestYubiKey].
/// [challenge] is the challenge bytes from the KDBX database header.
///
/// Returns the 20-byte HMAC-SHA1 response as a hex string suitable for
/// passing to `openDatabaseWithChallengeResponse`.
///
/// Per D-07: All WebUSB communication happens on the main thread via
/// dart:js_interop. The response hex is then passed to the WASM Worker
/// which uses ChallengeResponseKey::LocalChallenge for the KDF.
Future<String> yubikeyChallengeResponse(
  JSObject device,
  Uint8List challenge,
) async {
  // Open device and claim HID interface
  await (device.callMethod<JSPromise<JSAny?>>('open'.toJS)).toDart;

  try {
    await (device.callMethod<JSPromise<JSAny?>>(
      'selectConfiguration'.toJS,
      _yubiKeyConfiguration.toJS,
    ))
        .toDart;

    await (device.callMethod<JSPromise<JSAny?>>(
      'claimInterface'.toJS,
      _yubiKeyInterface.toJS,
    ))
        .toDart;

    // Build the HID report frame for slot 2 challenge-response
    // Frame format: [slot_cmd, challenge_length, ...challenge_bytes, ...padding]
    final frame = Uint8List(_hidReportSize);
    frame[0] = _slot2ChallengeCmd;
    frame[1] = challenge.length;
    for (var i = 0; i < challenge.length && i < _hidReportSize - 2; i++) {
      frame[i + 2] = challenge[i];
    }

    // Send challenge to YubiKey
    await (device.callMethod<JSPromise<JSAny?>>(
      'transferOut'.toJS,
      1.toJS, // endpoint 1 (OUT)
      frame.buffer.toJS,
    ))
        .toDart;

    // Read response from YubiKey
    final transferResult = await (device.callMethod<JSPromise<JSObject>>(
      'transferIn'.toJS,
      1.toJS, // endpoint 1 (IN)
      _hidReportSize.toJS,
    ))
        .toDart;

    // Extract the data view from the transfer result
    final dataView = transferResult.getProperty<JSDataView>('data'.toJS);
    final responseBytes = dataView.toDart.buffer.asUint8List();

    // HMAC-SHA1 produces 20 bytes
    final hmacResponse = responseBytes.sublist(0, 20);

    // Convert to hex string
    return hmacResponse
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  } finally {
    // Always close the device
    try {
      await (device.callMethod<JSPromise<JSAny?>>('close'.toJS)).toDart;
    } catch (_) {
      // Best-effort close
    }
  }
}
