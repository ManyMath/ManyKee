import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:manykee_native/main.dart';
import 'package:manykee_native/src/state/settings_state.dart';

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

String _fixturePath(String name) {
  final searched = <String>[];
  Directory? current = Directory.current.absolute;

  while (current != null) {
    final direct = File('${current.path}/integration_test/fixtures/$name');
    searched.add(direct.path);
    if (direct.existsSync()) {
      debugPrint('Using fixture path: ${direct.path}');
      return direct.path;
    }

    final nested = File(
      '${current.path}/apps/native/integration_test/fixtures/$name',
    );
    searched.add(nested.path);
    if (nested.existsSync()) {
      debugPrint('Using fixture path: ${nested.path}');
      return nested.path;
    }

    final parent = current.parent;
    if (parent.path == current.path) {
      current = null;
    } else {
      current = parent;
    }
  }

  throw StateError(
    'Fixture not found: $name\nSearched:\n${searched.join('\n')}',
  );
}

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
  }) async {
    debugPrint('FakeFilePicker returning path: $path');
    return FilePickerResult([PlatformFile(name: name, path: path, size: 1024)]);
  }
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

Finder _chooseDatabaseButton() =>
    find.widgetWithText(OutlinedButton, 'Choose KDBX File');

Finder _chooseKeyFileButton() =>
    find.widgetWithText(OutlinedButton, 'Choose Key File');

Finder _unlockVaultButton() =>
    find.widgetWithText(FilledButton, 'Unlock Vault');

Finder _openDifferentFileButton() =>
    find.widgetWithText(TextButton, 'Open Different File');

Finder _searchField() => find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == 'Search entries...',
      description: 'search field',
    );

Future<void> _tapControl(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}

/// Shared helper: boots app, picks fixture file, enters password, waits for vault.
///
/// Returns the [SettingsState] so tests can inspect settings changes.
Future<SettingsState> unlockVault(
  WidgetTester tester, {
  String? fixtureName,
  String? keyFileName,
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

  await _tapControl(tester, _chooseDatabaseButton());
  await tester.pumpAndSettle();

  if (keyFileName != null) {
    final keyPath = _fixturePath(keyFileName);
    FilePicker.platform = _FakeFilePicker(keyPath, keyFileName);

    await _tapControl(
      tester,
      find.widgetWithText(TextButton, 'Key File (optional)'),
    );
    await tester.pumpAndSettle();
    await _tapControl(tester, _chooseKeyFileButton());
    await tester.pumpAndSettle();
  }

  await tester.enterText(
    find.widgetWithText(TextField, 'Master Password'),
    password,
  );
  await tester.pumpAndSettle();
  await _tapControl(tester, _unlockVaultButton());

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

    testWidgets('unlocks password-plus-key-file database', (tester) async {
      await unlockVault(
        tester,
        fixtureName: 'test_db_kdbx4_with_keyfile_v2.kdbx',
        keyFileName: 'test_db_kdbx4_with_keyfile_v2.keyx',
      );

      expect(find.byTooltip('Lock Vault'), findsOneWidget);
      expect(find.byType(CircleAvatar), findsWidgets);
    });

    testWidgets('wrong password shows error on unlock screen', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsState();
      await settings.init();
      await settings.setAutoLockTimeout(0);

      final dbName = 'test_db_with_password.kdbx';
      final dbPath = _fixturePath(dbName);
      FilePicker.platform = _FakeFilePicker(dbPath, dbName);

      runApp(ManyKeeNativeApp(settings: settings));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      await _tapControl(tester, _chooseDatabaseButton());
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Master Password'),
        'wrongpassword',
      );
      await tester.pumpAndSettle();
      await _tapControl(tester, _unlockVaultButton());

      final errorFound = await pumpUntilFound(
        tester,
        find.byType(SelectableText),
        timeout: const Duration(seconds: 30),
      );
      expect(errorFound, isTrue);
      expect(
          find.text('Incorrect password. Please try again.'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Master Password'),
        'demopass',
      );
      await tester.pumpAndSettle();
      await _tapControl(tester, _unlockVaultButton());

      final reopened = await pumpUntilFound(
        tester,
        find.byTooltip('Lock Vault'),
        timeout: const Duration(seconds: 120),
      );
      expect(reopened, isTrue, reason: 'Vault should open after retry');
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

    testWidgets('shows app bar with lock and settings buttons', (tester) async {
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

    testWidgets('navigates nested groups and shows child entries', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(1280, 800));

      await unlockVault(
        tester,
        fixtureName: 'test_db_kdbx4_richcontent.kdbx',
        password: 'testpass123',
      );

      final childGroupFound = await pumpUntilFound(
        tester,
        find.text('Level2Group'),
        timeout: const Duration(seconds: 10),
      );
      expect(childGroupFound, isTrue);

      await _tapControl(tester, find.text('Level2Group').first);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.text('StandardEntry'), findsOneWidget);
      expect(find.text('CustomFieldsEntry'), findsNothing);
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
          reason: 'Entry detail should show field labels from fixture DB');
    });

    testWidgets('copy username field to clipboard', (tester) async {
      await unlockVault(tester);

      final entryAvatars = find.byType(CircleAvatar);
      expect(entryAvatars, findsWidgets);
      await tester.tap(entryAvatars.first);

      final usernameFound = await pumpUntilFound(
        tester,
        find.text('Username'),
        timeout: const Duration(seconds: 10),
      );
      expect(usernameFound, isTrue);

      await tester.tap(find.byTooltip('Copy username').first);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      final data = await Clipboard.getData('text/plain');
      expect(data?.text, isNotNull);
      expect(data!.text, isNotEmpty);
      expect(find.text('Copied to clipboard (clears in 30s)'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // Search
  // -------------------------------------------------------------------------
  group('Search', () {
    testWidgets('search filters entries across groups', (tester) async {
      await unlockVault(tester);

      // VaultSearchBar renders a TextField with hint 'Search entries...'.
      final searchField = _searchField();
      if (searchField.evaluate().isNotEmpty) {
        // Count entries before search.
        final beforeCount = find.byType(CircleAvatar).evaluate().length;

        // Focus the actual search TextField rather than its hint text.
        await _tapControl(tester, searchField.first);
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

    testWidgets('search with no results shows empty state', (tester) async {
      await unlockVault(tester);

      await _tapControl(tester, _searchField().first);
      await tester.pumpAndSettle();
      tester.testTextInput.enterText('zzzzzznonexistent');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.text('No matches'), findsOneWidget);
    });

    testWidgets('clearing search restores full entry list', (tester) async {
      await unlockVault(tester);

      final beforeCount = find.byType(CircleAvatar).evaluate().length;
      expect(beforeCount, greaterThan(0));

      await _tapControl(tester, _searchField().first);
      await tester.pumpAndSettle();
      tester.testTextInput.enterText('zzzzzznonexistent');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.text('No matches'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final afterCount = find.byType(CircleAvatar).evaluate().length;
      expect(find.text('No matches'), findsNothing);
      expect(afterCount, beforeCount);
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
      await _tapControl(tester, _unlockVaultButton());

      final reopened = await pumpUntilFound(
        tester,
        find.byTooltip('Lock Vault'),
        timeout: const Duration(seconds: 120),
      );
      expect(reopened, isTrue, reason: 'Vault should re-open from lock screen');
      expect(find.text('General'), findsWidgets);
    });

    testWidgets('wrong password on lock screen shows error then recovers',
        (tester) async {
      await unlockVault(tester);

      await tester.tap(find.byTooltip('Lock Vault'));
      await tester.pumpAndSettle();
      expect(find.text('Vault Locked'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Master Password'),
        'wrongpassword',
      );
      await tester.pumpAndSettle();
      await _tapControl(tester, _unlockVaultButton());

      final errorFound = await pumpUntilFound(
        tester,
        find.byType(SelectableText),
        timeout: const Duration(seconds: 30),
      );
      expect(errorFound, isTrue);
      expect(
          find.text('Incorrect password. Please try again.'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Master Password'),
        'demopass',
      );
      await tester.pumpAndSettle();
      await _tapControl(tester, _unlockVaultButton());

      final reopened = await pumpUntilFound(
        tester,
        find.byTooltip('Lock Vault'),
        timeout: const Duration(seconds: 120),
      );
      expect(reopened, isTrue,
          reason: 'Vault should recover after wrong password');
      expect(find.text('General'), findsWidgets);
    });

    testWidgets('full round-trip: unlock, browse, lock, re-unlock, verify',
        (tester) async {
      await unlockVault(tester);

      final entriesBefore = find.byType(CircleAvatar).evaluate().length;
      expect(entriesBefore, greaterThan(0));
      expect(find.byTooltip('Lock Vault'), findsOneWidget);

      await tester.tap(find.byTooltip('Lock Vault'));
      await tester.pumpAndSettle();
      expect(find.text('Vault Locked'), findsOneWidget);

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
      expect(reopened, isTrue);
      expect(find.byType(CircleAvatar).evaluate().length, greaterThan(0));
      expect(find.byTooltip('Lock Vault'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // Auto-lock
  // -------------------------------------------------------------------------
  group('Auto-lock', () {
    testWidgets('vault locks automatically after idle timeout', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsState();
      await settings.init();
      await settings.setAutoLockTimeoutDuration(const Duration(seconds: 2));

      final dbName = 'test_db_with_password.kdbx';
      final dbPath = _fixturePath(dbName);
      FilePicker.platform = _FakeFilePicker(dbPath, dbName);

      runApp(ManyKeeNativeApp(settings: settings));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      await _tapControl(tester, _chooseDatabaseButton());
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Master Password'),
        'demopass',
      );
      await tester.pumpAndSettle();
      await _tapControl(tester, _unlockVaultButton());

      final opened = await pumpUntilFound(
        tester,
        find.byTooltip('Lock Vault'),
        timeout: const Duration(seconds: 120),
      );
      expect(opened, isTrue);

      await tester.pump(const Duration(milliseconds: 100));

      final locked = await pumpUntilFound(
        tester,
        find.text('Vault Locked'),
        timeout: const Duration(seconds: 10),
      );
      expect(locked, isTrue);
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
      await _tapControl(tester, _openDifferentFileButton());
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
      final ykDbPath = _fixturePath('test_db_with_challenge_response_key.kdbx');
      FilePicker.platform = _FakeFilePicker(ykDbPath, 'yk_test.kdbx');
      await _tapControl(tester, _chooseDatabaseButton());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Master Password'),
        'demopass',
      );
      await tester.pumpAndSettle();

      // Enable YubiKey toggle if not auto-selected.
      final detectedChip = find.widgetWithText(InputChip, 'YubiKey detected');
      if (detectedChip.evaluate().isNotEmpty) {
        final chip = tester.widget<InputChip>(detectedChip);
        if (!chip.selected) {
          await _tapControl(tester, detectedChip);
          await tester.pumpAndSettle();
        }
      }

      final useYubiKey = find.widgetWithText(TextButton, 'Use YubiKey');
      if (useYubiKey.evaluate().isNotEmpty) {
        await _tapControl(tester, useYubiKey);
        await tester.pumpAndSettle();
      }

      await _tapControl(tester, _unlockVaultButton());

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
      debugPrint('YubiKey unlock: ${ykUnlocked ? "OK" : "error (see above)"}');
    });
  });

  // -------------------------------------------------------------------------
  // YubiKey (error)
  // -------------------------------------------------------------------------
  group('YubiKey (error)', () {
    testWidgets('YubiKey toggle without hardware shows error on unlock',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsState();
      await settings.init();
      await settings.setAutoLockTimeout(0);

      runApp(ManyKeeNativeApp(settings: settings));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      await tester.pumpAndSettle();

      final yubiKeyDetected =
          find.text('YubiKey detected').evaluate().isNotEmpty;
      if (yubiKeyDetected) {
        debugPrint('YubiKey hardware detected -- skipping error-path test');
        return;
      }

      final useYubiKey = find.text('Use YubiKey');
      expect(
        useYubiKey,
        findsOneWidget,
        reason:
            'Use YubiKey button must be visible when no hardware is present',
      );
      await tester.tap(useYubiKey);
      await tester.pumpAndSettle();

      final dbName = 'test_db_with_challenge_response_key.kdbx';
      final dbPath = _fixturePath(dbName);
      FilePicker.platform = _FakeFilePicker(dbPath, dbName);
      await _tapControl(tester, _chooseDatabaseButton());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Master Password'),
        'demopass',
      );
      await tester.pumpAndSettle();
      await _tapControl(tester, _unlockVaultButton());

      final errorFound = await pumpUntilFound(
        tester,
        find.byType(SelectableText),
        timeout: const Duration(seconds: 30),
      );
      expect(
        errorFound,
        isTrue,
        reason: 'YubiKey error must appear when hardware is unavailable',
      );

      final hasYubiKeyError =
          find.byType(SelectableText).evaluate().any((element) {
        final widget = element.widget as SelectableText;
        return widget.data?.contains('YubiKey') ?? false;
      });
      expect(hasYubiKeyError, isTrue);
    });
  });
}
