import 'dart:async';

import 'package:flutter/services.dart';

/// Manages clipboard copy operations with auto-clear after 30 seconds.
///
/// Per D-08: copied text is automatically cleared from the clipboard
/// after 30 seconds. The timer resets if the user copies again.
class ClipboardManager {
  Timer? _clearTimer;

  /// Copy [value] to the clipboard and start a 30-second auto-clear timer.
  ///
  /// Returns `true` on success, `false` if the clipboard operation failed
  /// (e.g. browser does not support the Clipboard API).
  Future<bool> copyWithAutoClear(String value) async {
    try {
      await Clipboard.setData(ClipboardData(text: value));
      _clearTimer?.cancel();
      _clearTimer = Timer(const Duration(seconds: 30), () {
        Clipboard.setData(const ClipboardData(text: ''));
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Cancel any pending auto-clear timer.
  void dispose() {
    _clearTimer?.cancel();
  }
}
