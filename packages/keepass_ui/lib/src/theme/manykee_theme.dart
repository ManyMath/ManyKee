import 'package:flutter/material.dart';

/// Material 3 theme for ManyKee apps.
///
/// Provides [light] and [dark] variants using the same seed color.
class ManyKeeTheme {
  ManyKeeTheme._();

  static const _seedColor = Color(0xFF2E7D32);

  static const _textTheme = TextTheme(
    bodyMedium: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      height: 1.5,
    ),
    labelSmall: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      height: 1.4,
    ),
    titleMedium: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      height: 1.3,
    ),
    titleLarge: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      height: 1.2,
    ),
  );

  /// Light theme matching the Phase 6 UI-SPEC color contract.
  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _seedColor,
        brightness: Brightness.light,
        surface: const Color(0xFFFAFAFA),
      ),
      textTheme: _textTheme,
    );
  }

  /// Dark theme using the same seed color with dark brightness.
  static ThemeData dark() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _seedColor,
        brightness: Brightness.dark,
      ),
      textTheme: _textTheme,
    );
  }
}
