import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class ClipboardManager {
  static Timer? _clearTimer;
  static Duration _clearDelay = const Duration(seconds: 30);
  static bool _pasteOnceEnabled = false;
  static bool _clearOnNextResume = false;
  static String _lastSuccessMessage = 'Copied to clipboard (clears in 30s)';

  static void configure({
    required Duration clearDelay,
    required bool pasteOnceEnabled,
  }) {
    _clearDelay = clearDelay;
    _pasteOnceEnabled = pasteOnceEnabled;
  }

  static Future<void> handleAppLifecycleState(AppLifecycleState state) async {
    if (state != AppLifecycleState.resumed || !_clearOnNextResume) {
      return;
    }
    _clearOnNextResume = false;
    _clearTimer?.cancel();
    await Clipboard.setData(const ClipboardData(text: ''));
  }

  String get lastSuccessMessage => _lastSuccessMessage;

  Future<bool> copyWithAutoClear(String value) async {
    try {
      await Clipboard.setData(ClipboardData(text: value));
      _clearTimer?.cancel();
      if (_clearDelay > Duration.zero) {
        _clearTimer = Timer(_clearDelay, () {
          Clipboard.setData(const ClipboardData(text: ''));
        });
      }
      _clearOnNextResume = _pasteOnceEnabled;
      _lastSuccessMessage = _buildSuccessMessage();
      return true;
    } catch (_) {
      return false;
    }
  }

  String _buildSuccessMessage() {
    if (_pasteOnceEnabled && _clearDelay > Duration.zero) {
      return 'Copied to clipboard (${_clearDelay.inSeconds}s clear or next resume)';
    }
    if (_pasteOnceEnabled) {
      return 'Copied to clipboard (clears on next resume)';
    }
    if (_clearDelay > Duration.zero) {
      return 'Copied to clipboard (clears in ${_clearDelay.inSeconds}s)';
    }
    return 'Copied to clipboard';
  }

  void dispose() {
    _clearTimer?.cancel();
    _clearTimer = null;
    _clearOnNextResume = false;
  }
}
