import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Toggles platform-level screen-capture protection while vault content is
/// visible.
///
/// Native handlers apply the strongest practical per-platform protection:
/// Android uses FLAG_SECURE, iOS/macOS show a privacy overlay when the app
/// resigns active, and Windows uses SetWindowDisplayAffinity. Unsupported
/// targets are no-ops.
class ScreenProtection {
  ScreenProtection._();

  static const MethodChannel channel = MethodChannel(
    'com.manykee.native/screen_protection',
  );

  static bool get _isSupportedPlatform {
    if (kIsWeb) return false;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.macOS ||
      TargetPlatform.windows => true,
      TargetPlatform.fuchsia || TargetPlatform.linux => false,
    };
  }

  static Future<void> setSecure(bool enabled) async {
    if (!_isSupportedPlatform) return;
    try {
      await channel.invokeMethod<void>('setSecure', {'enabled': enabled});
    } on MissingPluginException {
      // Widget tests and unsupported native shells may not register a handler.
    } on PlatformException {
      // This is defense-in-depth; vault correctness must not depend on it.
    }
  }
}
