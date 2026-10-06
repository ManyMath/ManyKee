// CTAPHID framing and HMAC-SHA1 challenge encoding for the YubiKey helpers
// in webusb_yubikey.dart. No JS interop here, so it can be tested on the VM.

import 'dart:typed_data';

const int ctapHidReportSize = 64;
const int ctapHidInit = 0x80 | 0x06; // 0x86
const int ctapHidMsg = 0x80 | 0x03; // 0x83
const int ctapHidKeepalive = 0x80 | 0x3B; // 0xBB
const int ctapHidError = 0x80 | 0x3F; // 0xBF

const int _initPayloadMax = ctapHidReportSize - 7; // 57
const int _contPayloadMax = ctapHidReportSize - 5; // 59
const int _maxSequence = 0x7F;

/// Size of the challenge buffer the YubiKey HMAC-SHA1 slot expects.
const int hmacChallengeSize = 64;

/// Pads [challenge] to [hmacChallengeSize] bytes the same way the native
/// path does (the `challenge_response` crate, as used by keepass-rs).
///
/// In variable-length HMAC mode the YubiKey strips trailing bytes equal to
/// the last byte of the buffer, so padding uses 0x00 unless the challenge
/// itself ends in 0x00, in which case it switches to 0xFF so the real
/// trailing zero survives.
Uint8List padHmacChallenge(List<int> challenge) {
  if (challenge.length > hmacChallengeSize) {
    throw ArgumentError.value(
      challenge.length,
      'challenge.length',
      'must be at most $hmacChallengeSize bytes',
    );
  }
  final padByte = challenge.isNotEmpty && challenge.last == 0x00 ? 0xFF : 0x00;
  return Uint8List(hmacChallengeSize)
    ..fillRange(0, hmacChallengeSize, padByte)
    ..setAll(0, challenge);
}

/// Builds the OTP applet APDU that asks [slot] (1 or 2) for an HMAC-SHA1
/// response to [challenge].
Uint8List buildHmacChallengeApdu(List<int> challenge, {int slot = 2}) {
  final int p1;
  switch (slot) {
    case 1:
      p1 = 0x30; // SLOT_CHAL_HMAC1
    case 2:
      p1 = 0x38; // SLOT_CHAL_HMAC2
    default:
      throw ArgumentError.value(slot, 'slot', 'must be 1 or 2');
  }
  final padded = padHmacChallenge(challenge);
  return Uint8List.fromList([
    0x00, 0x01, p1, 0x00, // CLA INS P1 P2
    padded.length, // Lc
    ...padded,
    0x16, // Le
  ]);
}

/// Splits [payload] into the CTAPHID initialization packet and as many
/// continuation packets as needed, each [ctapHidReportSize] bytes long.
List<Uint8List> encodeCtapHidFrames(
  List<int> channelId,
  int command,
  List<int> payload,
) {
  if (channelId.length != 4) {
    throw ArgumentError.value(channelId, 'channelId', 'must be 4 bytes');
  }
  if (payload.length > _initPayloadMax + (_maxSequence + 1) * _contPayloadMax) {
    throw ArgumentError.value(
      payload.length,
      'payload.length',
      'is too large for one CTAPHID message',
    );
  }

  final frames = <Uint8List>[];
  final init = Uint8List(ctapHidReportSize)
    ..setAll(0, channelId)
    ..[4] = command
    ..[5] = (payload.length >> 8) & 0xFF
    ..[6] = payload.length & 0xFF;
  var offset =
      payload.length < _initPayloadMax ? payload.length : _initPayloadMax;
  init.setRange(7, 7 + offset, payload);
  frames.add(init);

  var sequence = 0;
  while (offset < payload.length) {
    final remaining = payload.length - offset;
    final chunk = remaining < _contPayloadMax ? remaining : _contPayloadMax;
    final cont = Uint8List(ctapHidReportSize)
      ..setAll(0, channelId)
      ..[4] = sequence++;
    cont.setRange(5, 5 + chunk, payload, offset);
    frames.add(cont);
    offset += chunk;
  }
  return frames;
}

/// A CTAPHID ERROR frame sent by the authenticator.
class CtapHidException implements Exception {
  CtapHidException(this.errorCode);

  final int errorCode;

  static const _names = <int, String>{
    0x01: 'INVALID_CMD',
    0x02: 'INVALID_PAR',
    0x03: 'INVALID_LEN',
    0x04: 'INVALID_SEQ',
    0x05: 'MSG_TIMEOUT',
    0x06: 'CHANNEL_BUSY',
    0x0A: 'LOCK_REQUIRED',
    0x0B: 'INVALID_CHANNEL',
    0x7F: 'OTHER',
  };

  @override
  String toString() {
    final hex = errorCode.toRadixString(16).padLeft(2, '0');
    return 'CtapHidException: YubiKey reported CTAPHID error 0x$hex '
        '(${_names[errorCode] ?? 'unknown'})';
  }
}

/// Reassembles the response to one CTAPHID request from input reports.
///
/// Reports for other channels, KEEPALIVE frames (sent while the key waits
/// for a touch) and initialization frames for other commands are ignored.
/// An ERROR frame on the channel throws [CtapHidException].
class CtapHidResponseDecoder {
  CtapHidResponseDecoder(List<int> channelId, this.command)
      : _channelId = Uint8List.fromList(channelId);

  final Uint8List _channelId;

  /// The request's command byte (with bit 7 set) the response must echo.
  final int command;

  BytesBuilder? _buffer;
  int _expectedLength = 0;
  int _nextSequence = 0;

  /// Feeds one input report. Returns the complete payload once all of it
  /// has arrived, otherwise `null`.
  Uint8List? add(List<int> report) {
    if (report.length < 5) return null;
    for (var i = 0; i < 4; i++) {
      if (report[i] != _channelId[i]) return null;
    }

    final commandOrSequence = report[4];
    if (commandOrSequence & 0x80 != 0) {
      if (commandOrSequence == ctapHidKeepalive) return null;
      if (commandOrSequence == ctapHidError) {
        throw CtapHidException(report.length > 7 ? report[7] : 0x7F);
      }
      if (commandOrSequence != command || report.length < 7) return null;

      _expectedLength = (report[5] << 8) | report[6];
      _nextSequence = 0;
      _buffer = BytesBuilder(copy: false);
      _take(report, 7, _initPayloadMax);
    } else {
      final buffer = _buffer;
      if (buffer == null) return null;
      if (commandOrSequence != _nextSequence) {
        throw CtapHidException(0x04); // INVALID_SEQ
      }
      _nextSequence++;
      _take(report, 5, _contPayloadMax);
    }

    final buffer = _buffer!;
    if (buffer.length < _expectedLength) return null;
    _buffer = null;
    return buffer.takeBytes();
  }

  void _take(List<int> report, int start, int max) {
    final buffer = _buffer!;
    final remaining = _expectedLength - buffer.length;
    var end = start + (remaining < max ? remaining : max);
    if (end > report.length) end = report.length;
    if (end > start) buffer.add(Uint8List.fromList(report.sublist(start, end)));
  }
}
