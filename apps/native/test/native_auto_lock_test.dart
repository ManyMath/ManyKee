import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manykee_native/src/state/native_auto_lock.dart';

import 'helpers/fake_vault_state.dart';

class _TestVault extends FakeVaultState {
  int lockCalls = 0;

  /// Any state change that is not a lock/unlock (selection, cache refresh).
  void ping() => notifyListeners();

  @override
  Future<void> lock() {
    lockCalls++;
    return super.lock();
  }
}

void main() {
  const timeout = Duration(seconds: 5);

  _TestVault lockedVault(FakeAsync async) {
    final vault = _TestVault();
    vault.lock();
    async.flushMicrotasks();
    vault.lockCalls = 0;
    return vault;
  }

  void unlock(_TestVault vault, FakeAsync async) {
    vault.unlock(password: 'pw');
    async.flushMicrotasks();
  }

  test('arms on unlock and locks after the idle timeout', () {
    fakeAsync((async) {
      final vault = lockedVault(async);
      final autoLock = NativeAutoLock(vault: vault, timeout: timeout);

      async.elapse(const Duration(minutes: 1));
      expect(vault.lockCalls, 0, reason: 'nothing to lock while locked');

      unlock(vault, async);
      async.elapse(const Duration(seconds: 4));
      expect(vault.isLocked, isFalse);

      async.elapse(const Duration(seconds: 2));
      expect(vault.lockCalls, 1);
      expect(vault.isLocked, isTrue);

      autoLock.dispose();
    });
  });

  test('vault notifications do not extend the idle deadline', () {
    fakeAsync((async) {
      final vault = lockedVault(async);
      final autoLock = NativeAutoLock(vault: vault, timeout: timeout);
      unlock(vault, async);

      for (var i = 0; i < 6; i++) {
        async.elapse(const Duration(seconds: 1));
        vault.ping();
      }

      expect(vault.lockCalls, 1);
      autoLock.dispose();
    });
  });

  test('an unchanged timeout setting does not reset the countdown', () {
    fakeAsync((async) {
      final vault = lockedVault(async);
      final autoLock = NativeAutoLock(vault: vault, timeout: timeout);
      unlock(vault, async);

      async.elapse(const Duration(seconds: 4));
      autoLock.updateTimeout(timeout);
      async.elapse(const Duration(seconds: 2));

      expect(vault.lockCalls, 1);
      autoLock.dispose();
    });
  });

  test('user activity pushes the deadline back', () {
    fakeAsync((async) {
      final vault = lockedVault(async);
      final autoLock = NativeAutoLock(vault: vault, timeout: timeout);
      unlock(vault, async);

      async.elapse(const Duration(seconds: 4));
      autoLock.registerActivity();
      async.elapse(const Duration(seconds: 4));
      expect(vault.lockCalls, 0);

      async.elapse(const Duration(seconds: 2));
      expect(vault.lockCalls, 1);
      autoLock.dispose();
    });
  });

  test('a manual lock disarms the idle timer', () {
    fakeAsync((async) {
      final vault = lockedVault(async);
      final autoLock = NativeAutoLock(vault: vault, timeout: timeout);
      unlock(vault, async);

      autoLock.lockNow();
      async.flushMicrotasks();
      expect(vault.lockCalls, 1);

      async.elapse(const Duration(minutes: 1));
      expect(vault.lockCalls, 1);
      autoLock.dispose();
    });
  });
}
