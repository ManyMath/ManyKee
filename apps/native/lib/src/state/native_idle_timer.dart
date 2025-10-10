import 'dart:async';

import 'package:flutter/foundation.dart';

class NativeIdleTimer {
  Timer? _timer;
  Duration timeout;
  VoidCallback? _onLock;

  NativeIdleTimer({this.timeout = const Duration(minutes: 5)});

  void start(VoidCallback onLock) {
    _onLock = onLock;
    _resetTimer();
  }

  void resetTimer() {
    _resetTimer();
  }

  void _resetTimer() {
    _timer?.cancel();
    if (timeout != Duration.zero && _onLock != null) {
      _timer = Timer(timeout, _onLock!);
    }
  }

  void updateTimeout(Duration newTimeout) {
    timeout = newTimeout;
    _resetTimer();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _onLock = null;
  }

  void dispose() {
    stop();
  }
}
