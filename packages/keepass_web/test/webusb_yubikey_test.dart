@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:keepass_web/keepass_web.dart';
import 'package:test/test.dart';

@JS('eval')
external JSAny? _eval(JSString code);

/// A scripted YubiKey speaking CTAPHID over a WebHID-shaped object. It
/// reassembles request frames, records the HMAC APDU it received as hex,
/// and answers INIT, SELECT and the HMAC challenge. `mode` selects how the
/// challenge is answered.
JSObject _fakeYubiKey({String mode = 'ok'}) {
  return _eval('''
(() => {
  const listeners = new Set();
  const cid = [0x11, 0x22, 0x33, 0x44];
  let pending = null;
  const hex = (bytes) =>
    Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
  const emit = (chan, cmd, payload) => {
    const r = new Uint8Array(64);
    r.set(chan, 0);
    r[4] = cmd;
    r[5] = payload.length >> 8;
    r[6] = payload.length & 0xff;
    r.set(payload, 7);
    setTimeout(() => listeners.forEach((l) => l({ data: new DataView(r.buffer) })), 0);
  };
  const device = {
    mode: '$mode',
    hmacApduHex: null,
    framesSent: 0,
    open: async () => {},
    close: async () => {},
    addEventListener: (_, l) => listeners.add(l),
    removeEventListener: (_, l) => listeners.delete(l),
    sendReport: async (_, data) => {
      device.framesSent++;
      const b = ArrayBuffer.isView(data)
        ? new Uint8Array(data.buffer, data.byteOffset, data.byteLength)
        : new Uint8Array(data);
      if (b[4] & 0x80) {
        const len = (b[5] << 8) | b[6];
        pending = { cmd: b[4], len, payload: Array.from(b.slice(7, 7 + Math.min(57, len))) };
      } else {
        const need = pending.len - pending.payload.length;
        pending.payload.push(...b.slice(5, 5 + Math.min(59, need)));
      }
      if (pending.payload.length < pending.len) return;
      const msg = pending;
      pending = null;
      if (msg.cmd === 0x86) {
        emit([0xff, 0xff, 0xff, 0xff], 0x86, [...msg.payload.slice(0, 8), ...cid, 2, 5, 4, 3, 1]);
      } else if (msg.payload[1] === 0xa4) {
        emit(cid, 0x83, [5, 4, 3, 0x90, 0x00]);
      } else {
        device.hmacApduHex = hex(msg.payload);
        emit(cid, 0xbb, [0x02]); // KEEPALIVE: waiting for a touch
        if (device.mode === 'error') {
          emit(cid, 0xbf, [0x06]);
        } else if (device.mode === 'unconfigured') {
          emit(cid, 0x83, [0x69, 0x85]);
        } else {
          emit(cid, 0x83, [...new Array(20).fill(0xab), 0x90, 0x00]);
        }
      }
    },
  };
  return device;
})()
'''
      .toJS) as JSObject;
}

void _stubRequestDevice(String body) {
  _eval('''
Object.defineProperty(navigator, 'hid', {
  configurable: true,
  value: { requestDevice: async () => { $body } },
});
'''
      .toJS);
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

// A 32-byte KDF seed whose last byte is 0x00: the case unpadded challenges
// got wrong.
final _challenge = Uint8List.fromList([
  ...List.generate(31, (i) => i + 1),
  0x00,
]);

void main() {
  group('yubikeyChallengeResponse', () {
    test('sends a padded slot 2 challenge across two frames', () async {
      final device = _fakeYubiKey();

      final response = await yubikeyChallengeResponse(device, _challenge);

      expect(response, 'ab' * 20);
      final apdu = device.getProperty<JSString>('hmacApduHex'.toJS).toDart;
      expect(
        apdu,
        _hex([
          0x00,
          0x01,
          0x38,
          0x00,
          64,
          ...padHmacChallenge(_challenge),
          0x16
        ]),
      );
      // INIT + SELECT fit one frame each; the 70-byte HMAC APDU needs two.
      expect(device.getProperty<JSNumber>('framesSent'.toJS).toDartInt, 4);
    });

    test('targets slot 1 when asked', () async {
      final device = _fakeYubiKey();

      await yubikeyChallengeResponse(device, _challenge, slot: 1);

      final apdu = device.getProperty<JSString>('hmacApduHex'.toJS).toDart;
      expect(apdu.substring(0, 8), '00013000');
    });

    test('reports CTAPHID ERROR frames', () async {
      await expectLater(
        yubikeyChallengeResponse(_fakeYubiKey(mode: 'error'), _challenge),
        throwsA(
          isA<CtapHidException>().having((e) => e.errorCode, 'errorCode', 6),
        ),
      );
    });

    test('explains a rejected challenge status word', () async {
      await expectLater(
        yubikeyChallengeResponse(
          _fakeYubiKey(mode: 'unconfigured'),
          _challenge,
        ),
        throwsA(
          predicate(
            (e) =>
                e.toString().contains('6985') &&
                e.toString().contains('slot 2'),
          ),
        ),
      );
    });
  });

  group('requestYubiKey', () {
    test('returns null when the chooser is dismissed', () async {
      _stubRequestDevice('return [];');
      expect(await requestYubiKey(), isNull);

      _stubRequestDevice(
        "throw new DOMException('No device selected.', 'NotFoundError');",
      );
      expect(await requestYubiKey(), isNull);
    });

    test('propagates other failures such as SecurityError', () async {
      _stubRequestDevice("throw new DOMException('blocked', 'SecurityError');");

      Object? caught;
      try {
        await requestYubiKey();
      } catch (e) {
        caught = e;
      }
      expect(caught, isNotNull);
      expect(caught.toString(), contains('SecurityError'));
    });

    test('returns the picked device', () async {
      _stubRequestDevice("return [{ productName: 'YubiKey 5' }];");

      final device = await requestYubiKey();
      expect(
        device!.getProperty<JSString>('productName'.toJS).toDart,
        'YubiKey 5',
      );
    });
  });
}
