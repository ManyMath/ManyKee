import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:manyui/manyui.dart';

import 'state/settings_state.dart';

final themeModeProvider = Provider<MThemeMode>((ref) {
  return ref.watch(manyKeeSettingsProvider).themeMode;
});
