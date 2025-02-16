import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math';
import 'dart:typed_data';

const int _yubiKeyVendorId = 0x1050;
const int _ctapHidInit = 0x06 | 0x80; // 0x86
const int _ctapHidMsg = 0x03 | 0x80; // 0x83
const int _reportSize = 64;
const int _initPayloadMax = 57;

final Uint8List _otpAppletAid =
 Uint8List.fromList([0xA0, 0x00, 0x00, 0x05, 0x27, 0x20, 0x01]);

@JS('navigator.hid')
external JSObject? get _navigatorHid;

bool get isWebUsbAvailable => _navigatorHid != null;

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
 ))
 .toDart;

 final deviceArray = devices as JSArray;
 if (deviceArray.length == 0) return null;
 return deviceArray[0] as JSObject;
 } catch (e) {
 return null;
 }
}

Future<String> yubikeyChallengeResponse(
 JSObject device,
 Uint8List challenge,
) async {
 await (device.callMethod<JSPromise<JSAny?>>('open'.toJS)).toDart;

 try {
 final nonce = _randomBytes(8);
 final initPayload = Uint8List(8);
 initPayload.setAll(0, nonce);

 final initResponse = await _ctapHidExchange(
 device,
 Uint8List.fromList([0xFF, 0xFF, 0xFF, 0xFF]),
 _ctapHidInit,
 initPayload,
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
 _ctapHidMsg,
 selectApdu,
 );

 if (selectResp.length < 2 ||
 selectResp[selectResp.length - 2] != 0x90 ||
 selectResp[selectResp.length - 1] != 0x00) {
 throw Exception(
 'OTP applet SELECT failed: ${_hexEncode(selectResp)}',
 );
 }

 final hmacApdu = Uint8List.fromList([
 0x00, 0x01, 0x38, 0x00, // CLA INS P1 P2
 challenge.length, // Lc
 ...challenge, // Challenge bytes
 0x16, // Le = 22 (20 HMAC + 2 status)
 ]);
 final hmacResp = await _ctapHidExchange(
 device,
 channelId,
 _ctapHidMsg,
 hmacApdu,
 );

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
 // Build initialization packet
 final packet = Uint8List(_reportSize);
 packet.setAll(0, channelId); // bytes 0-3: channel
 packet[4] = command; // byte 4: command
 packet[5] = (payload.length >> 8) & 0xFF; // byte 5: length high
 packet[6] = payload.length & 0xFF; // byte 6: length low

 // Copy payload (max 57 bytes in init packet)
 final firstLen =
 payload.length < _initPayloadMax ? payload.length : _initPayloadMax;
 for (var i = 0; i < firstLen; i++) {
 packet[7 + i] = payload[i];
 }

 final completer = Completer<Uint8List>();

 void handleReport(JSObject event) {
 try {
 final dataView = event.getProperty<JSDataView>('data'.toJS);
 final bytes = dataView.toDart.buffer.asUint8List();
 if (bytes.length < 7) return;

 if (bytes[0] != channelId[0] ||
 bytes[1] != channelId[1] ||
 bytes[2] != channelId[2] ||
 bytes[3] != channelId[3]) {
 return;
 }

 if (bytes[4] & 0x80 == 0) return;

 final respLen = (bytes[5] << 8) | bytes[6];
 final dataEnd = 7 + respLen;
 final end = dataEnd < bytes.length ? dataEnd : bytes.length;
 final respPayload = Uint8List.fromList(bytes.sublist(7, end));

 if (!completer.isCompleted) {
 completer.complete(respPayload);
 }
 } catch (e) {
 if (!completer.isCompleted) {
 completer.completeError(e);
 }
 }
 }

 final jsCallback = handleReport.toJS;
 device.callMethod<JSAny?>(
 'addEventListener'.toJS,
 'inputreport'.toJS,
 jsCallback,
 );

 try {
 await (device.callMethod<JSPromise<JSAny?>>(
 'sendReport'.toJS,
 0.toJS,
 packet.buffer.toJS,
 ))
 .toDart;

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

Uint8List _randomBytes(int length) {
 final rng = Random.secure();
 return Uint8List.fromList(List.generate(length, (_) => rng.nextInt(256)));
}

String _hexEncode(Uint8List bytes) {
 return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
