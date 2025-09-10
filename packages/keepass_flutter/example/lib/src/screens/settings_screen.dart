import 'package:flutter/material.dart';
import 'package:keepass_ui/keepass_ui.dart' show Spacing;

import '../state/settings_state.dart';

class SettingsScreen extends StatelessWidget {
 final SettingsState settingsState;

 const SettingsScreen({super.key, required this.settingsState});

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
 padding: const EdgeInsets.only(left: Spacing.md, top: Spacing.lg),
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

 const Divider(),

 Padding(
 padding: const EdgeInsets.only(left: Spacing.md, top: Spacing.lg),
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
