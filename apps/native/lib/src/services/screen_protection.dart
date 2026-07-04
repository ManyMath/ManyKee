import 'dart:io';

import 'package:flutter/services.dart';

/// Toggles platform-level screen-capture protection while the vault is
/// unlocked, so an unlocked vault never appears in the app switcher,
/// screenshots, or screen recordings.
///
/// Backed by `MainActivity.kt` (Android, `FLAG_SECURE`),
/// `AppDelegate.swift` (iOS/macOS, obscuring overlay on resign-active), and
/// `flutter_window.cpp` (Windows, `SetWindowDisplayAffinity` with
/// `WDA_EXCLUDEFROMCAPTURE`). A no-op on platforms without a native handler
/// (Linux, no universal per-window capture-exclusion API across X11/Wayland
/// compositors, and tests).
class ScreenProtection {
  ScreenProtection._();

  static const MethodChannel _channel =
      MethodChannel('com.manykee.native/screen_protection');

  static bool get _isSupportedPlatform =>
      Platform.isAndroid ||
      Platform.isIOS ||
      Platform.isMacOS ||
      Platform.isWindows;

  static Future<void> setSecure(bool enabled) async {
    if (!_isSupportedPlatform) return;
    try {
      await _channel.invokeMethod<void>('setSecure', {'enabled': enabled});
    } on MissingPluginException {
      // No native handler registered (e.g. running in a widget test).
    } on PlatformException {
      // Best-effort: screen-capture protection is defense-in-depth, not
      // load-bearing for correctness.
    }
  }
}
