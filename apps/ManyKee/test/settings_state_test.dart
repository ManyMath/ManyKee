import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:manykee/src/state/settings_state.dart';
import 'package:manyui/manyui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('loader starts with defaults on first launch', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(manyKeeSettingsLoaderProvider.future);

    expect(container.read(manyKeeSettingsProvider), const ManyKeeSettings());
  });

  test('loader restores persisted settings', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'manykee.settings.themeMode': 'dark',
      'manykee.settings.autoLockMinutes': 15,
      'manykee.settings.lockOnBackground': false,
      'manykee.settings.screenProtection': false,
      'manykee.settings.clipboardSeconds': 60,
      'manykee.settings.clipboardPasteOnce': true,
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(manyKeeSettingsLoaderProvider.future);

    expect(
      container.read(manyKeeSettingsProvider),
      const ManyKeeSettings(
        themePreference: ManyKeeThemePreference.dark,
        autoLockTimeoutMinutes: 15,
        lockOnBackground: false,
        screenProtectionEnabled: false,
        clipboardAutoClearSeconds: 60,
        clipboardPasteOnce: true,
      ),
    );
  });

  test('loader falls back from invalid persisted options', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'manykee.settings.themeMode': 'sepia',
      'manykee.settings.autoLockMinutes': 99,
      'manykee.settings.clipboardSeconds': -1,
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(manyKeeSettingsLoaderProvider.future);

    expect(container.read(manyKeeSettingsProvider), const ManyKeeSettings());
  });

  test('controller updates settings and persists changes', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(manyKeeSettingsLoaderProvider.future);
    container.read(manyKeeSettingsPersistenceProvider);
    final controller = container.read(manyKeeSettingsControllerProvider);

    controller.setThemePreference(ManyKeeThemePreference.light);
    controller.setAutoLockTimeoutMinutes(30);
    controller.setLockOnBackground(false);
    controller.setScreenProtectionEnabled(false);
    controller.setClipboardAutoClearSeconds(10);
    controller.setClipboardPasteOnce(true);
    await Future<void>.delayed(Duration.zero);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('manykee.settings.themeMode'), 'light');
    expect(prefs.getInt('manykee.settings.autoLockMinutes'), 30);
    expect(prefs.getBool('manykee.settings.lockOnBackground'), false);
    expect(prefs.getBool('manykee.settings.screenProtection'), false);
    expect(prefs.getInt('manykee.settings.clipboardSeconds'), 10);
    expect(prefs.getBool('manykee.settings.clipboardPasteOnce'), true);
  });

  test('theme preference maps to ManyUI theme modes', () {
    expect(ManyKeeThemePreference.system.themeMode, MThemeMode.system);
    expect(ManyKeeThemePreference.light.themeMode, MThemeMode.light);
    expect(ManyKeeThemePreference.dark.themeMode, MThemeMode.dark);
  });
}
