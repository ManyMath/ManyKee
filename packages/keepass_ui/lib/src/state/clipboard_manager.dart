import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class ClipboardManager {
  static Timer? _clearTimer;
  static Duration _clearDelay = const Duration(seconds: 30);
  static bool _pasteOnceEnabled = false;
  static bool _clearOnNextResume = false;
  static String _lastSuccessMessage = 'Copied to clipboard (clears in 30s)';

  /// The value most recently placed on the clipboard by [copyWithAutoClear],
  /// while a clear (timer or paste-once) is still pending for it.
  static String? _pendingValue;

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
    _clearTimer = null;
    await _clearIfStillOurs();
  }

  String get lastSuccessMessage => _lastSuccessMessage;

  Future<bool> copyWithAutoClear(String value) async {
    try {
      await Clipboard.setData(ClipboardData(text: value));
      _pendingValue = value;
      _clearTimer?.cancel();
      _clearTimer = null;
      if (_clearDelay > Duration.zero) {
        _clearTimer = Timer(_clearDelay, () {
          _clearTimer = null;
          unawaited(_clearIfStillOurs());
        });
      }
      _clearOnNextResume = _pasteOnceEnabled;
      _lastSuccessMessage = _buildSuccessMessage();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Clears the clipboard only if it still holds the value we copied. Content
  /// the user copied from elsewhere in the meantime is left alone.
  static Future<void> _clearIfStillOurs() async {
    final expected = _pendingValue;
    _pendingValue = null;
    if (expected == null) {
      return;
    }
    try {
      final current = await Clipboard.getData(Clipboard.kTextPlain);
      if (current?.text != expected) {
        return;
      }
      await Clipboard.setData(const ClipboardData(text: ''));
    } catch (_) {
      // Clipboard access can fail (e.g. unsupported browser); nothing to do.
    }
  }

  String _buildSuccessMessage() {
    if (_pasteOnceEnabled && _clearDelay > Duration.zero) {
      return 'Copied. Clears in ${_clearDelay.inSeconds}s or when you return to the app.';
    }
    if (_pasteOnceEnabled) {
      return 'Copied. Clears when you return to the app.';
    }
    if (_clearDelay > Duration.zero) {
      return 'Copied to clipboard (clears in ${_clearDelay.inSeconds}s)';
    }
    return 'Copied to clipboard';
  }

  void dispose() {
    final hadPendingClear = _clearTimer != null;
    _clearTimer?.cancel();
    _clearTimer = null;
    _clearOnNextResume = false;
    if (hadPendingClear) {
      unawaited(_clearIfStillOurs());
    } else {
      _pendingValue = null;
    }
  }
}
