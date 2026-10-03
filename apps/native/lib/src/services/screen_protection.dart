import 'dart:io';

import 'package:flutter/services.dart';

/// Toggles platform-level screen-capture protection while the vault is
/// unlocked, keeping vault contents out of screenshots, screen recordings
/// and the app switcher where the platform supports it.
///
/// Coverage differs per platform:
///  * Android (`MainActivity.kt`, `FLAG_SECURE`): blocks screenshots,
///    recordings and the recents thumbnail.
///  * Windows (`flutter_window.cpp`, `SetWindowDisplayAffinity` with
///    `WDA_EXCLUDEFROMCAPTURE`): excludes the window from capture.
///  * iOS/macOS (`AppDelegate.swift`): only covers the window with an
///    overlay while the app is inactive (on iOS this hides the app-switcher
///    snapshot). Screenshots and recordings of the active app are not
///    blocked.
///  * Linux and tests: no-op (no universal per-window capture-exclusion API
///    across X11/Wayland compositors).
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
