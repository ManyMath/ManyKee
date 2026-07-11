import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:manyui/manyui.dart';

import '../state/settings_state.dart';

Future<void> showSettingsPage(BuildContext context) {
  return Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      pageBuilder: (context, animation, secondaryAnimation) =>
          const SettingsPage(),
    ),
  );
}

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(manyKeeSettingsProvider);
    final controller = ref.read(manyKeeSettingsControllerProvider);

    return MScaffold(
      header: MAppHeader(
        title: 'Settings',
        leading: MButton(
          variant: MButtonVariant.ghost,
          semanticLabel: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
          child: const MIcon(MIconData.chevronLeft),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: <Widget>[
              _Section(
                title: 'Security',
                children: <Widget>[
                  _SettingRow(
                    title: 'Auto-lock after',
                    description:
                        'Lock the open vault after a period without activity.',
                    trailing: _Select<int>(
                      key: ValueKey<int>(settings.autoLockTimeoutMinutes),
                      value: settings.autoLockTimeoutMinutes,
                      items: const <MSelectItem<int>>[
                        MSelectItem<int>(value: 1, label: '1 minute'),
                        MSelectItem<int>(value: 5, label: '5 minutes'),
                        MSelectItem<int>(value: 15, label: '15 minutes'),
                        MSelectItem<int>(value: 30, label: '30 minutes'),
                        MSelectItem<int>(value: 0, label: 'Never'),
                      ],
                      semanticLabel: 'Auto-lock timeout',
                      onChanged: (value) {
                        if (value != null) {
                          controller.setAutoLockTimeoutMinutes(value);
                        }
                      },
                    ),
                  ),
                  _SettingRow(
                    title: 'Lock when backgrounded',
                    description:
                        'Lock the open vault when the app is hidden or paused.',
                    trailing: MSwitch(
                      key: ValueKey<bool>(settings.lockOnBackground),
                      initialValue: settings.lockOnBackground,
                      semanticLabel: 'Lock when backgrounded',
                      onChanged: controller.setLockOnBackground,
                    ),
                  ),
                  _SettingRow(
                    title: 'Screen protection',
                    description:
                        'Hide unlocked vault content from app switchers and screen capture where supported.',
                    trailing: MSwitch(
                      key: ValueKey<bool>(settings.screenProtectionEnabled),
                      initialValue: settings.screenProtectionEnabled,
                      semanticLabel: 'Screen protection',
                      onChanged: controller.setScreenProtectionEnabled,
                    ),
                  ),
                  _SettingRow(
                    title: 'Clipboard auto-clear',
                    description:
                        'Choose how long copied secrets remain on the clipboard.',
                    trailing: _Select<int>(
                      key: ValueKey<int>(settings.clipboardAutoClearSeconds),
                      value: settings.clipboardAutoClearSeconds,
                      items: const <MSelectItem<int>>[
                        MSelectItem<int>(value: 10, label: '10 seconds'),
                        MSelectItem<int>(value: 30, label: '30 seconds'),
                        MSelectItem<int>(value: 60, label: '60 seconds'),
                        MSelectItem<int>(value: 0, label: 'Off'),
                      ],
                      semanticLabel: 'Clipboard auto-clear delay',
                      onChanged: (value) {
                        if (value != null) {
                          controller.setClipboardAutoClearSeconds(value);
                        }
                      },
                    ),
                  ),
                  _SettingRow(
                    title: 'Clear clipboard on resume',
                    description:
                        'Clear copied secrets the first time the app resumes.',
                    trailing: MSwitch(
                      key: ValueKey<bool>(settings.clipboardPasteOnce),
                      initialValue: settings.clipboardPasteOnce,
                      semanticLabel: 'Clear clipboard on resume',
                      onChanged: controller.setClipboardPasteOnce,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _Section(
                title: 'Appearance',
                children: <Widget>[
                  _SettingRow(
                    title: 'Theme',
                    description:
                        'Use the system appearance or pin ManyKee to one mode.',
                    trailing: _Select<ManyKeeThemePreference>(
                      key: ValueKey<ManyKeeThemePreference>(
                        settings.themePreference,
                      ),
                      value: settings.themePreference,
                      items: ManyKeeThemePreference.values
                          .map(
                            (preference) => MSelectItem<ManyKeeThemePreference>(
                              value: preference,
                              label: preference.label,
                            ),
                          )
                          .toList(growable: false),
                      semanticLabel: 'Theme',
                      onChanged: (value) {
                        if (value != null) {
                          controller.setThemePreference(value);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = MTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        MSectionHeader(title: title, titleStyle: theme.typography.title),
        const SizedBox(height: 12),
        MCard(
          child: Column(
            children: <Widget>[
              for (var i = 0; i < children.length; i++) ...<Widget>[
                children[i],
                if (i != children.length - 1) const MDivider(),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.title,
    required this.description,
    required this.trailing,
  });

  final String title;
  final String description;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return MPropertyRow(
      padding: const EdgeInsets.all(16),
      label: title,
      description: description,
      trailing: trailing,
    );
  }
}

class _Select<T> extends StatelessWidget {
  const _Select({
    required this.value,
    required this.items,
    required this.semanticLabel,
    required this.onChanged,
    super.key,
  });

  final T value;
  final List<MSelectItem<T>> items;
  final String semanticLabel;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      child: MSelect<T>(
        initialValue: value,
        items: items,
        semanticLabel: semanticLabel,
        onChanged: onChanged,
      ),
    );
  }
}
