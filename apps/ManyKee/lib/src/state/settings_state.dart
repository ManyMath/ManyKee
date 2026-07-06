import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:manyui/manyui.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefsThemeModeKey = 'manykee.settings.themeMode';
const _prefsAutoLockMinutesKey = 'manykee.settings.autoLockMinutes';
const _prefsLockOnBackgroundKey = 'manykee.settings.lockOnBackground';
const _prefsClipboardSecondsKey = 'manykee.settings.clipboardSeconds';
const _prefsClipboardPasteOnceKey = 'manykee.settings.clipboardPasteOnce';

const autoLockMinuteOptions = <int>[1, 5, 15, 30, 0];
const clipboardSecondOptions = <int>[10, 30, 60, 0];

enum ManyKeeThemePreference { system, light, dark }

extension ManyKeeThemePreferenceLabel on ManyKeeThemePreference {
  String get label {
    switch (this) {
      case ManyKeeThemePreference.system:
        return 'System';
      case ManyKeeThemePreference.light:
        return 'Light';
      case ManyKeeThemePreference.dark:
        return 'Dark';
    }
  }

  MThemeMode get themeMode {
    switch (this) {
      case ManyKeeThemePreference.system:
        return MThemeMode.system;
      case ManyKeeThemePreference.light:
        return MThemeMode.light;
      case ManyKeeThemePreference.dark:
        return MThemeMode.dark;
    }
  }
}

class ManyKeeSettings {
  const ManyKeeSettings({
    this.themePreference = ManyKeeThemePreference.system,
    this.autoLockTimeoutMinutes = 5,
    this.lockOnBackground = true,
    this.clipboardAutoClearSeconds = 30,
    this.clipboardPasteOnce = false,
  });

  final ManyKeeThemePreference themePreference;
  final int autoLockTimeoutMinutes;
  final bool lockOnBackground;
  final int clipboardAutoClearSeconds;
  final bool clipboardPasteOnce;

  Duration get autoLockTimeout {
    if (autoLockTimeoutMinutes <= 0) return Duration.zero;
    return Duration(minutes: autoLockTimeoutMinutes);
  }

  Duration get clipboardAutoClearDelay {
    if (clipboardAutoClearSeconds <= 0) return Duration.zero;
    return Duration(seconds: clipboardAutoClearSeconds);
  }

  MThemeMode get themeMode => themePreference.themeMode;

  ManyKeeSettings copyWith({
    ManyKeeThemePreference? themePreference,
    int? autoLockTimeoutMinutes,
    bool? lockOnBackground,
    int? clipboardAutoClearSeconds,
    bool? clipboardPasteOnce,
  }) {
    return ManyKeeSettings(
      themePreference: themePreference ?? this.themePreference,
      autoLockTimeoutMinutes:
          autoLockTimeoutMinutes ?? this.autoLockTimeoutMinutes,
      lockOnBackground: lockOnBackground ?? this.lockOnBackground,
      clipboardAutoClearSeconds:
          clipboardAutoClearSeconds ?? this.clipboardAutoClearSeconds,
      clipboardPasteOnce: clipboardPasteOnce ?? this.clipboardPasteOnce,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ManyKeeSettings &&
        other.themePreference == themePreference &&
        other.autoLockTimeoutMinutes == autoLockTimeoutMinutes &&
        other.lockOnBackground == lockOnBackground &&
        other.clipboardAutoClearSeconds == clipboardAutoClearSeconds &&
        other.clipboardPasteOnce == clipboardPasteOnce;
  }

  @override
  int get hashCode => Object.hash(
    themePreference,
    autoLockTimeoutMinutes,
    lockOnBackground,
    clipboardAutoClearSeconds,
    clipboardPasteOnce,
  );
}

final manyKeeSettingsProvider = StateProvider<ManyKeeSettings>(
  (ref) => const ManyKeeSettings(),
);

final manyKeeSettingsLoaderProvider = FutureProvider<void>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  ref.read(manyKeeSettingsProvider.notifier).state = ManyKeeSettings(
    themePreference: _themePreferenceFromName(
      prefs.getString(_prefsThemeModeKey),
    ),
    autoLockTimeoutMinutes: _validOption(
      prefs.getInt(_prefsAutoLockMinutesKey),
      autoLockMinuteOptions,
      fallback: 5,
    ),
    lockOnBackground: prefs.getBool(_prefsLockOnBackgroundKey) ?? true,
    clipboardAutoClearSeconds: _validOption(
      prefs.getInt(_prefsClipboardSecondsKey),
      clipboardSecondOptions,
      fallback: 30,
    ),
    clipboardPasteOnce: prefs.getBool(_prefsClipboardPasteOnceKey) ?? false,
  );
});

final manyKeeSettingsPersistenceProvider = Provider<void>((ref) {
  ref.listen<ManyKeeSettings>(manyKeeSettingsProvider, (previous, next) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsThemeModeKey, next.themePreference.name);
    await prefs.setInt(_prefsAutoLockMinutesKey, next.autoLockTimeoutMinutes);
    await prefs.setBool(_prefsLockOnBackgroundKey, next.lockOnBackground);
    await prefs.setInt(
      _prefsClipboardSecondsKey,
      next.clipboardAutoClearSeconds,
    );
    await prefs.setBool(_prefsClipboardPasteOnceKey, next.clipboardPasteOnce);
  }, fireImmediately: false);
});

class ManyKeeSettingsController {
  ManyKeeSettingsController(this._ref);

  final Ref _ref;

  void setThemePreference(ManyKeeThemePreference preference) {
    _set((settings) => settings.copyWith(themePreference: preference));
  }

  void toggleLightDarkTheme() {
    final current = _ref.read(manyKeeSettingsProvider).themePreference;
    setThemePreference(
      current == ManyKeeThemePreference.dark
          ? ManyKeeThemePreference.light
          : ManyKeeThemePreference.dark,
    );
  }

  void setAutoLockTimeoutMinutes(int minutes) {
    _set(
      (settings) => settings.copyWith(
        autoLockTimeoutMinutes: _validOption(
          minutes,
          autoLockMinuteOptions,
          fallback: settings.autoLockTimeoutMinutes,
        ),
      ),
    );
  }

  void setLockOnBackground(bool value) {
    _set((settings) => settings.copyWith(lockOnBackground: value));
  }

  void setClipboardAutoClearSeconds(int seconds) {
    _set(
      (settings) => settings.copyWith(
        clipboardAutoClearSeconds: _validOption(
          seconds,
          clipboardSecondOptions,
          fallback: settings.clipboardAutoClearSeconds,
        ),
      ),
    );
  }

  void setClipboardPasteOnce(bool value) {
    _set((settings) => settings.copyWith(clipboardPasteOnce: value));
  }

  void _set(ManyKeeSettings Function(ManyKeeSettings settings) update) {
    final notifier = _ref.read(manyKeeSettingsProvider.notifier);
    notifier.state = update(notifier.state);
  }
}

final manyKeeSettingsControllerProvider = Provider<ManyKeeSettingsController>((
  ref,
) {
  return ManyKeeSettingsController(ref);
});

ManyKeeThemePreference _themePreferenceFromName(String? name) {
  for (final value in ManyKeeThemePreference.values) {
    if (value.name == name) return value;
  }
  return ManyKeeThemePreference.system;
}

int _validOption(int? value, List<int> options, {required int fallback}) {
  if (value != null && options.contains(value)) return value;
  return fallback;
}
