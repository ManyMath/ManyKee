import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

/// Idle timer that triggers auto-lock on tab switch or inactivity.
///
/// Per D-06:
/// - Locks immediately when the tab becomes hidden (visibilitychange).
/// - Locks after [timeout] of no pointer/keyboard activity (default 5 min).
///
/// Event listeners are stored for proper cleanup (pitfall 3).
class IdleTimer {
  Timer? _timer;
  Duration timeout;
  VoidCallback? _onLock;

  JSFunction? _visibilityHandler;
  JSFunction? _pointerHandler;
  JSFunction? _keyHandler;

  IdleTimer({this.timeout = const Duration(minutes: 5)});

  /// Start monitoring for idle/visibility changes.
  ///
  /// [onLock] is called when the user should be locked out.
  void start(VoidCallback onLock) {
    _onLock = onLock;

    // Visibility change -- immediate lock when tab is hidden.
    _visibilityHandler = ((web.Event _) {
      if (web.document.hidden) {
        onLock();
      }
    }).toJS;
    web.document.addEventListener('visibilitychange', _visibilityHandler!);

    // Pointer and keyboard activity -- reset idle timer.
    _pointerHandler = ((web.Event _) {
      _resetTimer();
    }).toJS;
    _keyHandler = ((web.Event _) {
      _resetTimer();
    }).toJS;
    web.document.addEventListener('pointermove', _pointerHandler!);
    web.document.addEventListener('keydown', _keyHandler!);

    _resetTimer();
  }

  void _resetTimer() {
    _timer?.cancel();
    if (_onLock != null) {
      _timer = Timer(timeout, _onLock!);
    }
  }

  /// Update the idle timeout duration and restart the timer.
  void updateTimeout(Duration newTimeout) {
    timeout = newTimeout;
    _resetTimer();
  }

  /// Stop monitoring and remove all event listeners.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _onLock = null;

    if (_visibilityHandler != null) {
      web.document.removeEventListener('visibilitychange', _visibilityHandler!);
      _visibilityHandler = null;
    }
    if (_pointerHandler != null) {
      web.document.removeEventListener('pointermove', _pointerHandler!);
      _pointerHandler = null;
    }
    if (_keyHandler != null) {
      web.document.removeEventListener('keydown', _keyHandler!);
      _keyHandler = null;
    }
  }

  /// Dispose and clean up all resources.
  void dispose() {
    stop();
  }
}
