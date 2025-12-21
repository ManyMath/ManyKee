import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsState extends ChangeNotifier {
  static const _minutesKey = 'autoLockTimeout';
  static const _secondsKey = 'autoLockTimeoutSeconds';
  static const _clipboardSecondsKey = 'clipboardAutoClearSeconds';
  static const _pasteOnceKey = 'clipboardPasteOnce';

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    notifyListeners();
  }

  bool get isInitialized => _prefs != null;

  int get autoLockTimeoutMinutes => _prefs?.getInt(_minutesKey) ?? 5;

  Duration get autoLockTimeout {
    final seconds = _prefs?.getInt(_secondsKey);
    if (seconds != null) {
      if (seconds <= 0) return Duration.zero;
      return Duration(seconds: seconds);
    }
    final minutes = autoLockTimeoutMinutes;
    if (minutes == 0) return Duration.zero;
    return Duration(minutes: minutes);
  }

  Future<void> setAutoLockTimeout(int minutes) async {
    await _prefs?.setInt(_minutesKey, minutes);
    await _prefs?.remove(_secondsKey);
    notifyListeners();
  }

  Future<void> setAutoLockTimeoutDuration(Duration duration) async {
    await _prefs?.setInt(_secondsKey, duration.inSeconds);
    notifyListeners();
  }

  bool get lockOnBackground => _prefs?.getBool('lockOnBackground') ?? true;

  Future<void> setLockOnBackground(bool value) async {
    await _prefs?.setBool('lockOnBackground', value);
    notifyListeners();
  }

  int get clipboardAutoClearSeconds =>
      _prefs?.getInt(_clipboardSecondsKey) ?? 30;

  Duration get clipboardAutoClearDelay {
    final seconds = clipboardAutoClearSeconds;
    if (seconds <= 0) {
      return Duration.zero;
    }
    return Duration(seconds: seconds);
  }

  Future<void> setClipboardAutoClearSeconds(int seconds) async {
    await _prefs?.setInt(_clipboardSecondsKey, seconds);
    notifyListeners();
  }

  bool get clipboardPasteOnce => _prefs?.getBool(_pasteOnceKey) ?? false;

  Future<void> setClipboardPasteOnce(bool value) async {
    await _prefs?.setBool(_pasteOnceKey, value);
    notifyListeners();
  }

  String get themeMode => _prefs?.getString('themeMode') ?? 'system';

  Future<void> setThemeMode(String mode) async {
    await _prefs?.setString('themeMode', mode);
    notifyListeners();
  }
}
