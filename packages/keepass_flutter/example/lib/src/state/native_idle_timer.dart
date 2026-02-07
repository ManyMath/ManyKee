import 'dart:async';

import 'package:flutter/foundation.dart';

/// Native idle timer that triggers auto-lock after inactivity.
///
/// Pair with a `Listener` widget at the app root that calls [resetTimer]
/// on pointer/key events. The timer fires [onLock] after [timeout] of
/// no activity. Set timeout to Duration.zero to disable ("never").
class NativeIdleTimer {
  Timer? _timer;
  Duration timeout;
  VoidCallback? _onLock;

  NativeIdleTimer({this.timeout = const Duration(minutes: 5)});

  /// Start the idle timer. [onLock] is called when timeout expires.
  void start(VoidCallback onLock) {
    _onLock = onLock;
    _resetTimer();
  }

  /// Reset the timer (call on user activity -- pointer, key events).
  void resetTimer() {
    _resetTimer();
  }

  void _resetTimer() {
    _timer?.cancel();
    if (timeout != Duration.zero && _onLock != null) {
      _timer = Timer(timeout, _onLock!);
    }
  }

  /// Update the timeout duration and restart the timer.
  void updateTimeout(Duration newTimeout) {
    timeout = newTimeout;
    _resetTimer();
  }

  /// Stop the timer (call when vault is locked -- no need to track idle).
  void stop() {
    _timer?.cancel();
    _timer = null;
    _onLock = null;
  }

  /// Dispose all resources.
  void dispose() {
    stop();
  }
}
