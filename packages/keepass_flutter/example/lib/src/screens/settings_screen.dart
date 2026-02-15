import 'package:flutter/material.dart';
import 'package:keepass_ui/keepass_ui.dart'
    show
        AutofillProvider,
        BiometricProvider,
        NoAutofillProvider,
        NoBiometricProvider,
        Spacing;

import '../state/settings_state.dart';

class SettingsScreen extends StatelessWidget {
  final SettingsState settingsState;
  final BiometricProvider biometricProvider;
  final AutofillProvider autofillProvider;

  const SettingsScreen({
    super.key,
    required this.settingsState,
    this.biometricProvider = const NoBiometricProvider(),
    this.autofillProvider = const NoAutofillProvider(),
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: settingsState,
        builder: (context, _) {
          return ListView(
            children: [
              Padding(
                padding:
                    const EdgeInsets.only(left: Spacing.md, top: Spacing.lg),
                child: Text('Security', style: textTheme.titleMedium),
              ),
              ListTile(
                title: const Text('Auto-lock after'),
                trailing: DropdownButton<int>(
                  value: settingsState.autoLockTimeoutMinutes,
                  onChanged: (v) {
                    if (v != null) settingsState.setAutoLockTimeout(v);
                  },
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('1 minute')),
                    DropdownMenuItem(value: 5, child: Text('5 minutes')),
                    DropdownMenuItem(value: 15, child: Text('15 minutes')),
                    DropdownMenuItem(value: 30, child: Text('30 minutes')),
                    DropdownMenuItem(value: 0, child: Text('Never')),
                  ],
                ),
              ),
              SwitchListTile(
                title: const Text('Lock when backgrounded'),
                subtitle: const Text(
                  'Lock vault when app is minimized or sent to background',
                ),
                value: settingsState.lockOnBackground,
                onChanged: (v) => settingsState.setLockOnBackground(v),
              ),
              ListTile(
                title: const Text('Clipboard auto-clear'),
                subtitle: const Text(
                  'Choose how long copied secrets stay on the clipboard',
                ),
                trailing: DropdownButton<int>(
                  value: settingsState.clipboardAutoClearSeconds,
                  onChanged: (v) {
                    if (v != null) {
                      settingsState.setClipboardAutoClearSeconds(v);
                    }
                  },
                  items: const [
                    DropdownMenuItem(value: 10, child: Text('10 seconds')),
                    DropdownMenuItem(value: 30, child: Text('30 seconds')),
                    DropdownMenuItem(value: 60, child: Text('60 seconds')),
                    DropdownMenuItem(value: 0, child: Text('Off')),
                  ],
                ),
              ),
              SwitchListTile(
                title: const Text('Paste-once clipboard'),
                subtitle: const Text(
                  'Clear copied secrets on the first app resume after copying',
                ),
                value: settingsState.clipboardPasteOnce,
                onChanged: (v) => settingsState.setClipboardPasteOnce(v),
              ),
              SwitchListTile(
                title: const Text('Biometric unlock'),
                subtitle: Text(
                  biometricProvider is NoBiometricProvider
                      ? 'not supported on this platform'
                      : 'Use device biometrics to unlock the vault',
                ),
                value: false,
                onChanged:
                    biometricProvider is NoBiometricProvider ? null : (_) {},
              ),
              SwitchListTile(
                title: const Text('Autofill'),
                subtitle: Text(
                  autofillProvider is NoAutofillProvider
                      ? 'coming soon'
                      : 'Offer vault matches to system autofill',
                ),
                value: false,
                onChanged:
                    autofillProvider is NoAutofillProvider ? null : (_) {},
              ),
              const Divider(),
              Padding(
                padding:
                    const EdgeInsets.only(left: Spacing.md, top: Spacing.lg),
                child: Text('Appearance', style: textTheme.titleMedium),
              ),
              ListTile(
                title: const Text('Theme'),
                trailing: DropdownButton<String>(
                  value: settingsState.themeMode,
                  onChanged: (v) {
                    if (v != null) settingsState.setThemeMode(v);
                  },
                  items: const [
                    DropdownMenuItem(value: 'system', child: Text('System')),
                    DropdownMenuItem(value: 'light', child: Text('Light')),
                    DropdownMenuItem(value: 'dark', child: Text('Dark')),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
