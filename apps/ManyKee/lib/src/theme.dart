import 'package:flutter/widgets.dart' show Color;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:manyui/manyui.dart';

import 'state/settings_state.dart';

final themeModeProvider = Provider<MThemeMode>((ref) {
  return ref.watch(manyKeeSettingsProvider).themeMode;
});

final MThemeData manyKeeLightTheme = MThemeData.workbenchLight(
  primary: const Color(0xFF146C5A),
);

final MThemeData manyKeeDarkTheme = MThemeData.workbenchDark(
  primary: const Color(0xFF64C7AA),
);
