import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reactive settings state backed by SharedPreferencesWithCache.
class SettingsState extends ChangeNotifier {
 SharedPreferencesWithCache? _prefs;

 /// Initialize shared preferences. Call before runApp.
 Future<void> init() async {
 _prefs = await SharedPreferencesWithCache.create(
 cacheOptions: const SharedPreferencesWithCacheOptions(),
 );
 notifyListeners();
 }

 bool get isInitialized => _prefs != null;

/// Auto-lock timeout in minutes (1, 5, 15, 30, 0=never).
 int get autoLockTimeoutMinutes => _prefs?.getInt('autoLockTimeout') ?? 5;

 Duration get autoLockTimeout {
 final minutes = autoLockTimeoutMinutes;
 if (minutes == 0) return Duration.zero; // "never"
 return Duration(minutes: minutes);
 }

 Future<void> setAutoLockTimeout(int minutes) async {
 await _prefs?.setInt('autoLockTimeout', minutes);
 notifyListeners();
 }

 /// Whether to lock when app is backgrounded. Default: true.
 bool get lockOnBackground => _prefs?.getBool('lockOnBackground') ?? true;

 Future<void> setLockOnBackground(bool value) async {
 await _prefs?.setBool('lockOnBackground', value);
 notifyListeners();
 }

 /// Theme mode: "system", "light", "dark". Default: "system".
 String get themeMode => _prefs?.getString('themeMode') ?? 'system';

 Future<void> setThemeMode(String mode) async {
 await _prefs?.setString('themeMode', mode);
 notifyListeners();
 }
}
