import 'dart:typed_data';

import 'package:keepass_web/src/yubikey_ctaphid.dart';
import 'package:test/test.dart';

/// What a YubiKey slot in variable-length HMAC mode hashes: the 64-byte
/// buffer with every trailing byte equal to its last byte removed.
List<int> _variableModeInput(Uint8List buffer) {
  var end = buffer.length;
  final last = buffer.last;
  while (end > 0 && buffer[end - 1] == last) {
    end--;
  }
  return buffer.sublist(0, end);
}

Uint8List _seed(int lastByte) =>
    Uint8List.fromList([...List.generate(31, (i) => i + 1), lastByte]);

void main() {
  group('padHmacChallenge', () {
    test('pads with 0x00 to 64 bytes', () {
      final padded = padHmacChallenge(_seed(0x42));
      expect(padded, hasLength(64));
      expect(padded.sublist(0, 32), _seed(0x42));
      expect(padded.sublist(32), everyElement(0x00));
    });

    test('switches to 0xFF padding when the challenge ends in 0x00', () {
      final padded = padHmacChallenge(_seed(0x00));
      expect(padded.sublist(0, 32), _seed(0x00));
      expect(padded.sublist(32), everyElement(0xFF));
    });

    test('the key sees the original challenge for every last byte', () {
      for (var last = 0; last < 256; last++) {
        expect(
          _variableModeInput(padHmacChallenge(_seed(last))),
          _seed(last),
          reason: 'last byte 0x${last.toRadixString(16)}',
        );
      }
    });

    test('keeps a full 64-byte challenge and rejects longer ones', () {
      final full = Uint8List.fromList(List.generate(64, (i) => i));
      expect(padHmacChallenge(full), full);
      expect(() => padHmacChallenge(Uint8List(65)), throwsArgumentError);
    });
  });

  group('buildHmacChallengeApdu', () {
    test('targets slot 2 by default', () {
      final apdu = buildHmacChallengeApdu(_seed(1));
      expect(apdu.sublist(0, 5), [0x00, 0x01, 0x38, 0x00, 64]);
      expect(apdu.sublist(5, 69), padHmacChallenge(_seed(1)));
      expect(apdu.last, 0x16);
      expect(apdu, hasLength(70));
    });

    test('supports slot 1 and rejects other slots', () {
      expect(buildHmacChallengeApdu(_seed(1), slot: 1)[2], 0x30);
      expect(
          () => buildHmacChallengeApdu(_seed(1), slot: 3), throwsArgumentError);
    });
  });

  group('CTAPHID framing', () {
    const channel = [0x01, 0x02, 0x03, 0x04];

    test('splits a payload into init and continuation packets', () {
      final payload = List.generate(70, (i) => i);
      final frames = encodeCtapHidFrames(channel, ctapHidMsg, payload);

      expect(frames, hasLength(2));
      expect(frames.every((f) => f.length == ctapHidReportSize), isTrue);
      expect(frames[0].sublist(0, 7), [...channel, ctapHidMsg, 0x00, 70]);
      expect(frames[0].sublist(7), payload.sublist(0, 57));
      expect(frames[1].sublist(0, 5), [...channel, 0x00]);
      expect(frames[1].sublist(5, 18), payload.sublist(57));
      expect(frames[1].sublist(18), everyElement(0));
    });

    test('decodes a multi-packet response', () {
      final payload = List.generate(130, (i) => i & 0xFF);
      final decoder = CtapHidResponseDecoder(channel, ctapHidMsg);
      final frames = encodeCtapHidFrames(channel, ctapHidMsg, payload);
      expect(frames, hasLength(3));

      expect(decoder.add(frames[0]), isNull);
      expect(decoder.add(frames[1]), isNull);
      expect(decoder.add(frames[2]), payload);
    });

    test('ignores keepalives, other channels and other commands', () {
      final decoder = CtapHidResponseDecoder(channel, ctapHidMsg);
      final response = encodeCtapHidFrames(channel, ctapHidMsg, [0x90, 0x00]);

      final keepalive = encodeCtapHidFrames(channel, ctapHidKeepalive, [0x02]);
      final otherChannel =
          encodeCtapHidFrames([9, 9, 9, 9], ctapHidMsg, [0x6A, 0x82]);
      final otherCommand = encodeCtapHidFrames(channel, ctapHidInit, [1, 2]);

      expect(decoder.add(keepalive.single), isNull);
      expect(decoder.add(otherChannel.single), isNull);
      expect(decoder.add(otherCommand.single), isNull);
      expect(decoder.add(response.single), [0x90, 0x00]);
    });

    test('surfaces ERROR frames', () {
      final decoder = CtapHidResponseDecoder(channel, ctapHidMsg);
      final error = encodeCtapHidFrames(channel, ctapHidError, [0x06]);

      expect(
        () => decoder.add(error.single),
        throwsA(
          isA<CtapHidException>()
              .having((e) => e.errorCode, 'errorCode', 0x06)
              .having((e) => e.toString(), 'toString', contains('BUSY')),
        ),
      );
    });

    test('rejects out-of-order continuation packets', () {
      final decoder = CtapHidResponseDecoder(channel, ctapHidMsg);
      final frames =
          encodeCtapHidFrames(channel, ctapHidMsg, List.filled(130, 1));

      decoder.add(frames[0]);
      expect(() => decoder.add(frames[2]), throwsA(isA<CtapHidException>()));
    });
  });
}
