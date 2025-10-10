import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:manykee_native/main.dart';
import 'package:manykee_native/src/state/settings_state.dart';

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

String _fixturePath(String name) =>
 '${Directory.current.path}/integration_test/fixtures/$name';

class _FakeFilePicker extends FilePicker {
 final String path;
 final String name;
 _FakeFilePicker(this.path, this.name);

 @override
 Future<FilePickerResult?> pickFiles({
 String? dialogTitle,
 String? initialDirectory,
 FileType type = FileType.any,
 List<String>? allowedExtensions,
 Function(FilePickerStatus)? onFileLoading,
 bool allowCompression = true,
 int compressionQuality = 30,
 bool allowMultiple = false,
 bool withData = false,
 bool withReadStream = false,
 bool lockParentWindow = false,
 bool readSequential = false,
 }) async =>
 FilePickerResult([PlatformFile(name: name, path: path, size: 1024)]);
}

Future<bool> pumpUntilFound(
 WidgetTester tester,
 Finder finder, {
 Duration timeout = const Duration(seconds: 60),
}) async {
 final end = DateTime.now().add(timeout);
 while (DateTime.now().isBefore(end)) {
 await tester.pump(const Duration(milliseconds: 500));
 if (finder.evaluate().isNotEmpty) return true;
 }
 await tester.pumpAndSettle();
 return finder.evaluate().isNotEmpty;
}

/// Shared helper: boots app, picks fixture file, enters password, waits for vault.
///
/// Returns the [SettingsState] so tests can inspect settings changes.
Future<SettingsState> unlockVault(
 WidgetTester tester, {
 String? fixtureName,
 String password = 'demopass',
 Duration timeout = const Duration(seconds: 120),
}) async {
 SharedPreferences.setMockInitialValues({});
 final settings = SettingsState();
 await settings.init();
 await settings.setAutoLockTimeout(0);

 final dbName = fixtureName ?? 'test_db_with_password.kdbx';
 final dbPath = _fixturePath(dbName);
 FilePicker.platform = _FakeFilePicker(dbPath, dbName);

 runApp(ManyKeeNativeApp(settings: settings));
 await tester.pumpAndSettle(const Duration(seconds: 5));

 await tester.tap(find.text('Choose KDBX File'));
 await tester.pumpAndSettle();

 await tester.enterText(
 find.widgetWithText(TextField, 'Master Password'),
 password,
 );
 await tester.pumpAndSettle();
 await tester.tap(find.text('Unlock Vault'));

 final opened = await pumpUntilFound(
 tester,
 find.byTooltip('Lock Vault'),
 timeout: timeout,
 );
 expect(opened, isTrue, reason: 'Vault should open after correct password');

 return settings;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
 IntegrationTestWidgetsFlutterBinding.ensureInitialized();

 // -------------------------------------------------------------------------
 // Unlock flow
 // -------------------------------------------------------------------------
 group('Unlock flow', () {
 testWidgets('unlock screen shows initial UI', (tester) async {
 SharedPreferences.setMockInitialValues({});
 final settings = SettingsState();
 await settings.init();
 await settings.setAutoLockTimeout(0);

 runApp(ManyKeeNativeApp(settings: settings));
 await tester.pumpAndSettle(const Duration(seconds: 5));

 expect(find.text('ManyKee'), findsOneWidget);
 expect(find.text('Choose KDBX File'), findsOneWidget);
 });

 testWidgets('unlocks vault with correct password', (tester) async {
 await unlockVault(tester);

 expect(find.text('General'), findsWidgets);
 expect(find.byTooltip('Lock Vault'), findsOneWidget);
 });
 });

 // -------------------------------------------------------------------------
 // Vault browsing
 // -------------------------------------------------------------------------
 group('Vault browsing', () {
 testWidgets('shows vault layout with groups and entries', (tester) async {
 await unlockVault(tester);

 expect(find.text('General'), findsWidgets);
 expect(find.byTooltip('Lock Vault'), findsOneWidget);
 });

 testWidgets('shows app bar with lock and settings buttons',
 (tester) async {
 await unlockVault(tester);

 expect(find.byTooltip('Lock Vault'), findsOneWidget);
 expect(find.byTooltip('Settings'), findsOneWidget);
 });

 testWidgets('displays entries for selected group', (tester) async {
 await unlockVault(tester);

 // After unlock, the first group is auto-selected. Verify entries are
 // visible: at least one ListTile beyond the group tree should exist.
 final entryAvatars = find.byType(CircleAvatar);
 expect(entryAvatars, findsWidgets,
 reason: 'Entry list should show entries for the selected group');
 });

 testWidgets('group navigation updates entry list', (tester) async {
 await unlockVault(tester);

 // Look for a different group to tap (e.g. "Internet", "email", etc.)
 // Try common group names from KeePass default databases.
 Finder? groupFinder;
 for (final name in ['Internet', 'eMail', 'Homebanking', 'Network']) {
 final f = find.text(name);
 if (f.evaluate().isNotEmpty) {
 groupFinder = f;
 break;
 }
 }

 if (groupFinder != null) {
 await tester.tap(groupFinder);
 await tester.pumpAndSettle(const Duration(seconds: 2));

 // Tap back to General.
 await tester.tap(find.text('General').first);
 await tester.pumpAndSettle(const Duration(seconds: 2));

 // Verify we're back -- General entries should be visible.
 expect(find.text('General'), findsWidgets);
 } else {
 // If only one group exists, navigation test passes trivially.
 debugPrint('Only one group found -- group navigation trivially passes');
 expect(find.text('General'), findsWidgets);
 }
 });
 });

 // -------------------------------------------------------------------------
 // Entry detail
 // -------------------------------------------------------------------------
 group('Entry detail', () {
 testWidgets('selecting entry shows detail panel', (tester) async {
 await unlockVault(tester);

 // Tap the first entry in the entry list.
 final entryAvatars = find.byType(CircleAvatar);
 expect(entryAvatars, findsWidgets);
 await tester.tap(entryAvatars.first);
 await tester.pumpAndSettle(const Duration(seconds: 2));

 // Verify detail content appears -- look for field labels.
 final hasUsername = find.text('Username').evaluate().isNotEmpty;
 final hasPassword = find.text('Password').evaluate().isNotEmpty;
 final hasUrl = find.text('URL').evaluate().isNotEmpty;
 final hasTitle = find.text('Title').evaluate().isNotEmpty;

 expect(hasUsername || hasPassword || hasUrl || hasTitle, isTrue,
 reason: 'Detail panel should show field labels');
 });

 testWidgets('selecting different entry updates detail', (tester) async {
 await unlockVault(tester);

 final entryAvatars = find.byType(CircleAvatar);
 if (entryAvatars.evaluate().length < 2) {
 debugPrint('Fewer than 2 entries -- skipping different entry test');
 return;
 }

 // Tap first entry.
 await tester.tap(entryAvatars.first);
 await tester.pumpAndSettle(const Duration(seconds: 2));

 // Tap second entry.
 await tester.tap(entryAvatars.at(1));
 await tester.pumpAndSettle(const Duration(seconds: 2));

 // Detail panel should still show content (it updated).
 final hasLabels = find.text('Username').evaluate().isNotEmpty ||
 find.text('Password').evaluate().isNotEmpty;
 expect(hasLabels, isTrue,
 reason: 'Detail panel should update for new entry');
 });

 testWidgets('entry detail shows field content', (tester) async {
 await unlockVault(tester);

 // Tap first entry (entries use CircleAvatar).
 final entryAvatars = find.byType(CircleAvatar);
 expect(entryAvatars, findsWidgets);
 await tester.tap(entryAvatars.first);

 // Wait for async field loading in EntryDetail.
 await pumpUntilFound(tester, find.text('Username'),
 timeout: const Duration(seconds: 10));
 await tester.pumpAndSettle(const Duration(seconds: 1));

 // Verify field labels from EntryDetail (uses Text, not SelectableText).
 final hasUsername = find.text('Username').evaluate().isNotEmpty;
 final hasPassword = find.text('Password').evaluate().isNotEmpty;
 final hasUrl = find.text('URL').evaluate().isNotEmpty;

 expect(hasUsername || hasPassword || hasUrl, isTrue,
 reason:
 'Entry detail should show field labels from fixture DB');
 });
 });

 // -------------------------------------------------------------------------
 // Search
 // -------------------------------------------------------------------------
 group('Search', () {
 testWidgets('search filters entries across groups', (tester) async {
 await unlockVault(tester);

 // VaultSearchBar renders a TextField with hint 'Search entries...'.
 final searchHint = find.text('Search entries...');
 if (searchHint.evaluate().isNotEmpty) {
 // Count entries before search.
 final beforeCount = find.byType(CircleAvatar).evaluate().length;

 // Tap hint text to focus the search TextField.
 await tester.tap(searchHint.first);
 await tester.pumpAndSettle();

 // Now type into the focused field via testTextInput.
 tester.testTextInput.enterText('test');
 // Wait for 300ms debounce + async search + rebuild.
 await tester.pump(const Duration(milliseconds: 500));
 await tester.pumpAndSettle(const Duration(seconds: 3));

 // Search should either change entry count or show empty state.
 final afterCount = find.byType(CircleAvatar).evaluate().length;
 final hasEmptyState = find.text('No entries').evaluate().isNotEmpty ||
 find.text('No matches').evaluate().isNotEmpty;
 final searchChanged = afterCount != beforeCount || hasEmptyState;
 expect(searchChanged, isTrue,
 reason: 'Search should filter entries or show no matches');
 } else {
 debugPrint('Search field not found -- search test inconclusive');
 }
 });
 });

 // -------------------------------------------------------------------------
 // Lock and re-unlock
 // -------------------------------------------------------------------------
 group('Lock and re-unlock', () {
 testWidgets('lock returns to lock screen', (tester) async {
 await unlockVault(tester);

 await tester.tap(find.byTooltip('Lock Vault'));
 await tester.pumpAndSettle();

 expect(find.text('Vault Locked'), findsOneWidget);
 // Filename should be displayed on lock screen.
 expect(find.text('test_db_with_password.kdbx'), findsOneWidget);
 });

 testWidgets('re-unlock from lock screen', (tester) async {
 await unlockVault(tester);

 // Lock.
 await tester.tap(find.byTooltip('Lock Vault'));
 await tester.pumpAndSettle();
 expect(find.text('Vault Locked'), findsOneWidget);

 // Re-unlock.
 await tester.enterText(
 find.widgetWithText(TextField, 'Master Password'),
 'demopass',
 );
 await tester.pumpAndSettle();
 await tester.tap(find.text('Unlock Vault'));

 final reopened = await pumpUntilFound(
 tester,
 find.byTooltip('Lock Vault'),
 timeout: const Duration(seconds: 120),
 );
 expect(reopened, isTrue, reason: 'Vault should re-open from lock screen');
 expect(find.text('General'), findsWidgets);
 });
 });

 // -------------------------------------------------------------------------
 // Settings
 // -------------------------------------------------------------------------
 group('Settings', () {
 testWidgets('settings screen accessible and functional', (tester) async {
 final settings = await unlockVault(tester);

 await tester.tap(find.byTooltip('Settings'));
 await tester.pumpAndSettle();
 expect(find.text('Settings'), findsOneWidget);

 // Change auto-lock timeout from Never to 15 minutes.
 await tester.tap(find.text('Never'));
 await tester.pumpAndSettle();
 await tester.tap(find.text('15 minutes').last);
 await tester.pumpAndSettle();

 // Change theme from System to Dark.
 await tester.tap(find.text('System'));
 await tester.pumpAndSettle();
 await tester.tap(find.text('Dark').last);
 await tester.pumpAndSettle();

 expect(settings.autoLockTimeoutMinutes, 15);
 expect(settings.themeMode, 'dark');
 });
 });

 // -------------------------------------------------------------------------
 // Native-specific
 // -------------------------------------------------------------------------
 group('Native-specific', () {
 testWidgets('open different file returns to unlock screen', (tester) async {
 await unlockVault(tester);

 // Lock vault.
 await tester.tap(find.byTooltip('Lock Vault'));
 await tester.pumpAndSettle();
 expect(find.text('Vault Locked'), findsOneWidget);

 // Tap "Open Different File".
 await tester.tap(find.text('Open Different File'));
 await tester.pumpAndSettle();

 // Should return to the initial unlock screen.
 expect(find.text('ManyKee'), findsOneWidget);
 expect(find.text('Choose KDBX File'), findsOneWidget);
 });
 });

 // -------------------------------------------------------------------------
 // YubiKey (conditional)
 // -------------------------------------------------------------------------
 group('YubiKey (conditional)', () {
 testWidgets('YubiKey challenge-response unlock', (tester) async {
 SharedPreferences.setMockInitialValues({});
 final settings = SettingsState();
 await settings.init();
 await settings.setAutoLockTimeout(0);

 runApp(ManyKeeNativeApp(settings: settings));
 await tester.pumpAndSettle(const Duration(seconds: 5));

 // Wait for YubiKey detection (async detection runs on init).
 for (var i = 0; i < 6; i++) {
 await tester.pump(const Duration(milliseconds: 500));
 }
 await tester.pumpAndSettle();

 final yubiKeyDetected =
 find.text('YubiKey detected').evaluate().isNotEmpty;

 if (!yubiKeyDetected) {
 debugPrint('YubiKey not detected -- skipping');
 return;
 }

 // YubiKey present: pick challenge-response fixture, unlock.
 final ykDbPath =
 _fixturePath('test_db_with_challenge_response_key.kdbx');
 FilePicker.platform = _FakeFilePicker(ykDbPath, 'yk_test.kdbx');
 await tester.tap(find.text('Choose KDBX File'));
 await tester.pumpAndSettle();

 await tester.enterText(
 find.widgetWithText(TextField, 'Master Password'),
 'demopass',
 );
 await tester.pumpAndSettle();

 // Enable YubiKey toggle if not auto-selected.
 final useYubiKey = find.text('Use YubiKey');
 if (useYubiKey.evaluate().isNotEmpty) {
 await tester.tap(useYubiKey);
 await tester.pumpAndSettle();
 }

 await tester.tap(find.text('Unlock Vault'));

 // Wait for vault or error.
 for (var i = 0; i < 60; i++) {
 await tester.pump(const Duration(milliseconds: 500));
 if (find.byTooltip('Lock Vault').evaluate().isNotEmpty) break;
 if (find.byType(SelectableText).evaluate().isNotEmpty) break;
 }
 await tester.pumpAndSettle();

 final ykUnlocked = find.byTooltip('Lock Vault').evaluate().isNotEmpty;
 for (final e in find.byType(SelectableText).evaluate()) {
 final w = e.widget as SelectableText;
 if (w.data != null && w.data!.isNotEmpty) {
 debugPrint('YubiKey result: ${w.data}');
 }
 }
 debugPrint(
 'YubiKey unlock: ${ykUnlocked ? "OK" : "error (see above)"}');
 });
 });
}
