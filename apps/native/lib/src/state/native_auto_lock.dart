import 'dart:async';

import 'package:keepass_ui/keepass_ui.dart';

import 'native_idle_timer.dart';

/// Drives the idle auto-lock for [vault].
///
/// The idle timer is armed once, on the locked -> unlocked edge, and
/// disarmed when the vault locks. Ordinary vault notifications (selection,
/// search, cache refreshes) do not touch it; only [registerActivity]
/// pushes the deadline back.
class NativeAutoLock {
  NativeAutoLock({required this.vault, required Duration timeout})
      : _idleTimer = NativeIdleTimer(timeout: timeout) {
    vault.addListener(_sync);
    _sync();
  }

  final VaultState vault;
  final NativeIdleTimer _idleTimer;
  bool _armed = false;

  Duration get timeout => _idleTimer.timeout;

  /// Applies a new idle timeout. A no-op when [timeout] is unchanged, so
  /// unrelated settings changes do not reset the countdown.
  void updateTimeout(Duration timeout) {
    if (timeout == _idleTimer.timeout) return;
    _idleTimer.updateTimeout(timeout);
  }

  /// User input (pointer, keyboard) pushes the idle deadline back.
  void registerActivity() {
    if (_armed) _idleTimer.resetTimer();
  }

  /// Locks the vault now (lock button, app backgrounded).
  void lockNow() {
    if (vault.isLocked) return;
    _idleTimer.stop();
    unawaited(vault.lock());
  }

  void _sync() {
    final shouldArm = !vault.isLocked;
    if (shouldArm == _armed) return;
    _armed = shouldArm;
    if (shouldArm) {
      _idleTimer.start(lockNow);
    } else {
      _idleTimer.stop();
    }
  }

  void dispose() {
    vault.removeListener(_sync);
    _idleTimer.dispose();
  }
}
