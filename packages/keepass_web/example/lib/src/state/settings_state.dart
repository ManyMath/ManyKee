import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

class SettingsState extends ChangeNotifier {
  static const _minutesKey = 'autoLockTimeout';
  static const _clipboardSecondsKey = 'clipboardAutoClearSeconds';
  static const _pasteOnceKey = 'clipboardPasteOnce';

  Future<void> init() async {
    notifyListeners();
  }

  bool get isInitialized => true;

  int get autoLockTimeoutMinutes =>
      int.tryParse(web.window.localStorage.getItem(_minutesKey) ?? '') ?? 5;

  Duration get autoLockTimeout {
    final minutes = autoLockTimeoutMinutes;
    if (minutes == 0) {
      return const Duration(days: 365);
    }
    return Duration(minutes: minutes);
  }

  Future<void> setAutoLockTimeout(int minutes) async {
    web.window.localStorage.setItem(_minutesKey, minutes.toString());
    notifyListeners();
  }

  int get clipboardAutoClearSeconds =>
      int.tryParse(
        web.window.localStorage.getItem(_clipboardSecondsKey) ?? '',
      ) ??
      30;

  Duration get clipboardAutoClearDelay {
    final seconds = clipboardAutoClearSeconds;
    if (seconds <= 0) {
      return Duration.zero;
    }
    return Duration(seconds: seconds);
  }

  Future<void> setClipboardAutoClearSeconds(int seconds) async {
    web.window.localStorage.setItem(_clipboardSecondsKey, seconds.toString());
    notifyListeners();
  }

  bool get clipboardPasteOnce =>
      web.window.localStorage.getItem(_pasteOnceKey) == 'true';

  Future<void> setClipboardPasteOnce(bool value) async {
    web.window.localStorage.setItem(_pasteOnceKey, value.toString());
    notifyListeners();
  }
}
