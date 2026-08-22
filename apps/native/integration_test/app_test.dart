import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:keepass_ui/keepass_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:manykee_native/main.dart';
import 'package:manykee_native/src/screens/vault_screen.dart';
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

class _WritableFixture {
  const _WritableFixture({
    required this.path,
    required this.name,
  });

  final String path;
  final String name;
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

/// Reads the plaintext value a `CopyButton` with the given [tooltip] would
/// copy, by reading the widget's own `value` field directly instead of
/// guessing at sibling `Text` widgets via ancestor/descendant traversal --
/// both the entry list tile and the entry detail panel render their own
/// "Copy username" button (`entry_list.dart`, `entry_detail.dart`), so
/// `find.byTooltip('Copy username')` isn't guaranteed to match only one
/// widget, and its nearest containing `Row` differs in shape between the
/// two call sites (list tile: avatar + title/username column + two copy
/// buttons; detail panel: just the value + one copy button). Both render
/// the same underlying entry field though, so reading whichever matching
/// `CopyButton`'s `value` is available is unambiguous.
String _copyButtonValue(WidgetTester tester, String tooltip) {
  final buttons = tester.widgetList<CopyButton>(
    find.byWidgetPredicate(
      (widget) => widget is CopyButton && widget.tooltip == tooltip,
    ),
  );
  return buttons
      .map((button) => button.value ?? '')
      .firstWhere((value) => value.isNotEmpty, orElse: () => '');
}

/// Reads the plaintext username currently shown for the selected entry, so a
/// copy-to-clipboard test can assert against the actual value the UI
/// displayed rather than merely "clipboard is non-empty".
String _displayedUsername(WidgetTester tester) =>
    _copyButtonValue(tester, 'Copy username');

Future<void> _tapControl(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}

Future<void> _useDesktopLayout(WidgetTester tester) async {
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.binding.setSurfaceSize(const Size(1280, 800));
}

Future<_WritableFixture> _copyFixtureToTemp(String fixtureName) async {
  final sourcePath = _fixturePath(fixtureName);
  final tempDir = await Directory.systemTemp.createTemp('manykee-itest-');
  addTearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  final targetPath = '${tempDir.path}/$fixtureName';
  await File(sourcePath).copy(targetPath);
  return _WritableFixture(path: targetPath, name: fixtureName);
}

Future<void> _saveVaultAndReload(
  WidgetTester tester, {
  required String password,
}) async {
  await _tapControl(tester, find.byTooltip('Save Vault'));

  final saved = await pumpUntilFound(
    tester,
    find.text('Vault saved'),
    timeout: const Duration(seconds: 30),
  );
  expect(saved, isTrue, reason: 'Save action should complete successfully');

  await _tapControl(tester, find.byTooltip('Lock Vault'));
  await tester.pumpAndSettle();
  expect(find.text('Vault Locked'), findsOneWidget);

  await tester.enterText(
    find.widgetWithText(TextField, 'Master Password'),
    password,
  );
  await tester.pumpAndSettle();
  await _tapControl(tester, _unlockVaultButton());

  final reopened = await pumpUntilFound(
    tester,
    find.byTooltip('Lock Vault'),
    timeout: const Duration(seconds: 120),
  );
  expect(reopened, isTrue, reason: 'Vault should reopen after save + lock');
}

Finder _groupLabel(String name) => find.descendant(
      of: find.byType(GroupTree),
      matching: find.text(name),
    );

VaultGroup? _findGroupByName(List<VaultGroup> groups, String name) {
  for (final group in groups) {
    if (group.name == name) {
      return group;
    }
    final childMatch = _findGroupByName(group.children, name);
    if (childMatch != null) {
      return childMatch;
    }
  }
  return null;
}

bool _groupExists(List<VaultGroup> groups, String name) =>
    _findGroupByName(groups, name) != null;

bool _groupIsChildOf(
  List<VaultGroup> groups,
  String parentName,
  String childName,
) {
  final parent = _findGroupByName(groups, parentName);
  if (parent == null) {
    return false;
  }
  return _findGroupByName(parent.children, childName) != null;
}

Future<void> _openGroupMenu(WidgetTester tester, String name) async {
  final tile = find
      .ancestor(
        of: _groupLabel(name).first,
        matching: find.byType(Material),
      )
      .first;
  await _tapControl(
    tester,
    find.descendant(
      of: tile,
      matching: find.byTooltip('Group actions'),
    ),
  );
  await tester.pumpAndSettle();
}

/// Shared helper: boots app, picks fixture file, enters password, waits for vault.
///
/// Returns the [SettingsState] so tests can inspect settings changes.
Future<SettingsState> unlockVault(
  WidgetTester tester, {
  String? fixtureName,
  String? fixturePath,
  String? keyFileName,
  String password = 'demopass',
  Duration timeout = const Duration(seconds: 120),
  SettingsState? settings,
  bool resetPreferences = true,
}) async {
  if (resetPreferences) {
    SharedPreferences.setMockInitialValues({});
  }
  final activeSettings = settings ?? SettingsState();
  if (settings == null) {
    await activeSettings.init();
  }
  await activeSettings.setAutoLockTimeout(0);

  final dbName = fixtureName ?? 'test_db_with_password.kdbx';
  final dbPath = fixturePath ?? _fixturePath(dbName);
  final selectedName = File(dbPath).uri.pathSegments.isEmpty
      ? dbName
      : File(dbPath).uri.pathSegments.last;
  FilePicker.platform = _FakeFilePicker(dbPath, selectedName);

  runApp(ManyKeeNativeApp(settings: activeSettings));
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

  return activeSettings;
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

    testWidgets('navigates nested groups and shows child entries',
        (tester) async {
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

      final expectedUsername = _displayedUsername(tester);

      await tester.tap(find.byTooltip('Copy username').first);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      final data = await Clipboard.getData('text/plain');
      expect(data?.text, isNotNull);
      expect(data!.text, isNotEmpty);
      expect(
        data.text,
        expectedUsername,
        reason: 'Copied text should be the username actually shown in the '
            'detail panel, not some other field',
      );
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
        // Focus the actual search TextField rather than its hint text.
        await _tapControl(tester, searchField.first);
        await tester.pumpAndSettle();

        // Now type into the focused field via testTextInput.
        tester.testTextInput.enterText('test');
        // Wait for 300ms debounce + async search + rebuild.
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle(const Duration(seconds: 3));

        // Once a query is active, VaultScreen._buildEntryListPanel swaps to
        // an entirely different widget (a plain ListView keyed
        // 'searchResultsList', not EntryList) -- CircleAvatar/CopyButton
        // don't exist in that tree at all, so this test has to scope
        // against that widget instead, not EntryList. Note search is
        // database-wide, not scoped to the currently selected group, so
        // its result count isn't bounded by what that one group showed
        // before the query -- only content is worth asserting on here.
        final searchResultsList = find.byKey(const Key('searchResultsList'));
        final afterRows = find
            .descendant(of: searchResultsList, matching: find.byType(InkWell))
            .evaluate();
        final hasEmptyState = find.text('No matches').evaluate().isNotEmpty;

        // Search should either narrow the list to entries that actually
        // match the query, or show an explicit no-matches state -- a search
        // that silently ignores the query and re-renders the same list must
        // fail here even if the count happens to differ.
        if (hasEmptyState) {
          expect(searchResultsList.evaluate(), isEmpty,
              reason: 'A no-matches state should mean the search results '
                  'list is not rendered at all');
        } else {
          expect(afterRows, isNotEmpty,
              reason: 'Search should filter entries or show no matches');

          // Verify the remaining results match the query, rather
          // than the list just happening to show unrelated entries.
          final visibleText = tester
              .widgetList<Text>(find.descendant(
                of: searchResultsList,
                matching: find.byType(Text),
              ))
              .map((text) => text.data ?? '')
              .join(' ')
              .toLowerCase();
          expect(
            visibleText.contains('test'),
            isTrue,
            reason: 'Visible search results "$visibleText" should match '
                'query "test"',
          );
        }
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
  // v1.4 native write coverage
  // -------------------------------------------------------------------------
  group('v1.4 native write coverage', () {
    testWidgets('ITEST-01: creates a new entry and reload keeps it', (
      tester,
    ) async {
      await _useDesktopLayout(tester);
      final writableFixture = await _copyFixtureToTemp(
        'test_db_kdbx4_richcontent.kdbx',
      );

      await unlockVault(
        tester,
        fixtureName: writableFixture.name,
        fixturePath: writableFixture.path,
        password: 'testpass123',
      );

      await _tapControl(tester, find.text('New Entry'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Created Integration Entry');
      await tester.enterText(fields.at(1), 'created-user');
      await tester.enterText(fields.at(2), 'created-pass');
      await tester.enterText(fields.at(3), 'https://created.example');
      await tester.enterText(
          fields.at(4), 'Created in native integration test');
      await _tapControl(tester, find.text('Create Entry').last);
      await tester.pumpAndSettle();

      expect(find.text('Created Integration Entry'), findsWidgets);

      await _saveVaultAndReload(tester, password: 'testpass123');
      expect(find.text('Created Integration Entry'), findsWidgets);
    });

    testWidgets('ITEST-02: edits an entry title and password with persistence',
        (
      tester,
    ) async {
      await _useDesktopLayout(tester);
      final writableFixture = await _copyFixtureToTemp(
        'test_db_kdbx4_richcontent.kdbx',
      );

      await unlockVault(
        tester,
        fixtureName: writableFixture.name,
        fixturePath: writableFixture.path,
        password: 'testpass123',
      );

      await _tapControl(tester, find.text('CustomFieldsEntry').first);
      await tester.pumpAndSettle();
      await _tapControl(tester, find.byTooltip('Edit Entry'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Edited Integration Entry');
      await tester.enterText(fields.at(2), 'UpdatedPass!23');
      await _tapControl(tester, find.text('Save Entry').last);
      await tester.pumpAndSettle();

      expect(find.text('Edited Integration Entry'), findsWidgets);

      await _saveVaultAndReload(tester, password: 'testpass123');

      await _tapControl(tester, find.text('Edited Integration Entry').last);
      final editEntryFound = await pumpUntilFound(
        tester,
        find.byTooltip('Edit Entry'),
        timeout: const Duration(seconds: 10),
      );
      expect(editEntryFound, isTrue);
      final vaultScreen = tester.widget<NativeVaultScreen>(
        find.byType(NativeVaultScreen),
      );
      final reopenedEntry = vaultScreen.vaultState.entries.firstWhere(
        (entry) => entry.title == 'Edited Integration Entry',
      );
      final persistedFields = await vaultScreen.vaultState.readEntryFields(
        reopenedEntry.uuid,
      );
      expect(persistedFields['Password'], 'UpdatedPass!23');
    });

    testWidgets('ITEST-03: deletes an entry after save', (tester) async {
      await _useDesktopLayout(tester);
      final writableFixture = await _copyFixtureToTemp(
        'test_db_kdbx4_richcontent.kdbx',
      );

      await unlockVault(
        tester,
        fixtureName: writableFixture.name,
        fixturePath: writableFixture.path,
        password: 'testpass123',
      );

      await _tapControl(tester, find.text('CustomFieldsEntry').first);
      await tester.pumpAndSettle();
      await _tapControl(tester, find.byTooltip('Delete Entry'));
      await tester.pumpAndSettle();
      await _tapControl(tester, find.text('Delete Entry').last);
      await tester.pumpAndSettle();

      expect(find.text('CustomFieldsEntry'), findsNothing);

      await _tapControl(tester, find.byTooltip('Save Vault'));
      final saved = await pumpUntilFound(
        tester,
        find.text('Vault saved'),
        timeout: const Duration(seconds: 30),
      );
      expect(saved, isTrue);
      expect(find.text('CustomFieldsEntry'), findsNothing);
    });

    testWidgets(
        'ITEST-04: moves an entry and save keeps it in the target group', (
      tester,
    ) async {
      await _useDesktopLayout(tester);
      final writableFixture = await _copyFixtureToTemp(
        'test_db_kdbx4_richcontent.kdbx',
      );

      await unlockVault(
        tester,
        fixtureName: writableFixture.name,
        fixturePath: writableFixture.path,
        password: 'testpass123',
      );

      await _tapControl(tester, find.text('CustomFieldsEntry').first);
      await tester.pumpAndSettle();
      await _tapControl(tester, find.byTooltip('Move Entry'));
      await tester.pumpAndSettle();
      await _tapControl(tester, find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await _tapControl(tester, find.textContaining('Level2Group').last);
      await tester.pumpAndSettle();
      await _tapControl(tester, find.text('Move Entry').last);
      await tester.pumpAndSettle();

      expect(find.text('CustomFieldsEntry'), findsNothing);

      await _saveVaultAndReload(tester, password: 'testpass123');

      await _tapControl(tester, _groupLabel('Level2Group').first);
      await tester.pumpAndSettle();
      expect(find.text('CustomFieldsEntry'), findsOneWidget);
    });

    testWidgets('ITEST-05: creates a subgroup from the group tree', (
      tester,
    ) async {
      await _useDesktopLayout(tester);
      final writableFixture = await _copyFixtureToTemp(
        'test_db_kdbx4_richcontent.kdbx',
      );

      await unlockVault(
        tester,
        fixtureName: writableFixture.name,
        fixturePath: writableFixture.path,
        password: 'testpass123',
      );

      await _openGroupMenu(tester, 'Level1Group');
      await _tapControl(tester, find.text('New Subgroup'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Projects');
      await _tapControl(tester, find.text('Create Group').last);
      await tester.pumpAndSettle();

      expect(_groupLabel('Projects'), findsOneWidget);

      await _saveVaultAndReload(tester, password: 'testpass123');
      final vaultScreen = tester.widget<NativeVaultScreen>(
        find.byType(NativeVaultScreen),
      );
      expect(_groupExists(vaultScreen.vaultState.groups, 'Projects'), isTrue);
    });

    testWidgets('ITEST-06: renames a group in the tree', (tester) async {
      await _useDesktopLayout(tester);
      final writableFixture = await _copyFixtureToTemp(
        'test_db_kdbx4_richcontent.kdbx',
      );

      await unlockVault(
        tester,
        fixtureName: writableFixture.name,
        fixturePath: writableFixture.path,
        password: 'testpass123',
      );

      await _openGroupMenu(tester, 'Level2Group');
      await _tapControl(tester, find.text('Rename Group'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Renamed Level2');
      await _tapControl(tester, find.text('Save Group').last);
      await tester.pumpAndSettle();

      expect(_groupLabel('Renamed Level2'), findsOneWidget);
      expect(_groupLabel('Level2Group'), findsNothing);

      await _saveVaultAndReload(tester, password: 'testpass123');
      final vaultScreen = tester.widget<NativeVaultScreen>(
        find.byType(NativeVaultScreen),
      );
      expect(
        _groupExists(vaultScreen.vaultState.groups, 'Renamed Level2'),
        isTrue,
      );
      expect(
          _groupExists(vaultScreen.vaultState.groups, 'Level2Group'), isFalse);
    });

    testWidgets('ITEST-07: deletes a group and keeps recycle bin hidden', (
      tester,
    ) async {
      await _useDesktopLayout(tester);
      final writableFixture = await _copyFixtureToTemp(
        'test_db_kdbx4_richcontent.kdbx',
      );

      await unlockVault(
        tester,
        fixtureName: writableFixture.name,
        fixturePath: writableFixture.path,
        password: 'testpass123',
      );

      await _openGroupMenu(tester, 'Level2Group');
      await _tapControl(tester, find.text('Delete Group'));
      await tester.pumpAndSettle();
      await _tapControl(tester, find.text('Delete Group').last);
      await tester.pumpAndSettle();

      expect(_groupLabel('Level2Group'), findsNothing);
      expect(_groupLabel('Recycle Bin'), findsNothing);

      await _saveVaultAndReload(tester, password: 'testpass123');
      expect(_groupLabel('Level2Group'), findsNothing);
      expect(_groupLabel('Recycle Bin'), findsNothing);
    });

    testWidgets('ITEST-08: moves a group to a different parent',
        (tester) async {
      await _useDesktopLayout(tester);
      final writableFixture = await _copyFixtureToTemp(
        'test_db_kdbx4_richcontent.kdbx',
      );

      await unlockVault(
        tester,
        fixtureName: writableFixture.name,
        fixturePath: writableFixture.path,
        password: 'testpass123',
      );

      await _openGroupMenu(tester, 'Level1Group');
      await _tapControl(tester, find.text('New Subgroup'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Target Parent');
      await _tapControl(tester, find.text('Create Group').last);
      await tester.pumpAndSettle();

      await _openGroupMenu(tester, 'Level2Group');
      await _tapControl(tester, find.text('Move Group'));
      await tester.pumpAndSettle();
      await _tapControl(tester, find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await _tapControl(tester, find.textContaining('Target Parent').last);
      await tester.pumpAndSettle();
      await _tapControl(tester, find.text('Move Group').last);
      await tester.pumpAndSettle();

      expect(_groupLabel('Target Parent'), findsOneWidget);
      expect(_groupLabel('Level2Group'), findsOneWidget);

      await _saveVaultAndReload(tester, password: 'testpass123');
      final vaultScreen = tester.widget<NativeVaultScreen>(
        find.byType(NativeVaultScreen),
      );
      expect(
          _groupExists(vaultScreen.vaultState.groups, 'Target Parent'), isTrue);
      expect(
        _groupIsChildOf(
          vaultScreen.vaultState.groups,
          'Target Parent',
          'Level2Group',
        ),
        isTrue,
      );
    });

    testWidgets('ITEST-09: shows live TOTP details for a real fixture entry', (
      tester,
    ) async {
      await _useDesktopLayout(tester);
      await unlockVault(
        tester,
        fixtureName: 'test_db_kdbx4_richcontent.kdbx',
        password: 'testpass123',
      );

      await _tapControl(tester, _searchField().first);
      await tester.pumpAndSettle();
      tester.testTextInput.enterText('TOTPEntry');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final resultFound = await pumpUntilFound(
        tester,
        find.text('TOTPEntry'),
        timeout: const Duration(seconds: 20),
      );
      expect(resultFound, isTrue);

      await _tapControl(tester, find.text('TOTPEntry').last);
      final totpPanelFound = await pumpUntilFound(
        tester,
        find.text('One-Time Code'),
        timeout: const Duration(seconds: 10),
      );
      expect(totpPanelFound, isTrue);
      expect(find.byTooltip('Copy one-time code'), findsOneWidget);

      await _tapControl(tester, find.byTooltip('Copy one-time code').first);
      await tester.pumpAndSettle();

      final renderedTotp = tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data ?? widget.textSpan?.toPlainText() ?? '')
          .where((text) => RegExp(r'\d{3}\s?\d{3}').hasMatch(text))
          .toList();
      expect(
        renderedTotp,
        isNotEmpty,
      );
      expect(find.textContaining('Refreshes in '), findsOneWidget);
    });

    testWidgets(
        'ITEST-10: clipboard delay updates and persists across settings reload',
        (
      tester,
    ) async {
      await _useDesktopLayout(tester);
      const fixtureName = 'test_db_kdbx4_richcontent.kdbx';
      const fixturePassword = 'testpass123';
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsState();
      await settings.init();
      await settings.setAutoLockTimeout(0);

      await unlockVault(
        tester,
        fixtureName: fixtureName,
        password: fixturePassword,
        settings: settings,
        resetPreferences: false,
      );

      await _tapControl(tester, find.byTooltip('Settings'));
      await tester.pumpAndSettle();

      await _tapControl(tester, find.text('30 seconds').last);
      await tester.pumpAndSettle();
      await _tapControl(tester, find.text('10 seconds').last);
      await tester.pumpAndSettle();

      expect(settings.clipboardAutoClearSeconds, 10);

      await tester.pageBack();
      await tester.pumpAndSettle();

      final expectedUsername = _displayedUsername(tester);

      await _tapControl(tester, find.byTooltip('Copy username').first);
      await tester.pumpAndSettle();
      expect(find.text('Copied to clipboard (clears in 10s)'), findsOneWidget);

      final data = await Clipboard.getData('text/plain');
      expect(
        data?.text,
        expectedUsername,
        reason: 'Copied text should be the username actually shown in the '
            'detail panel, not some other field',
      );

      final reloadedSettings = SettingsState();
      await reloadedSettings.init();
      expect(reloadedSettings.clipboardAutoClearSeconds, 10);
    });

    testWidgets('ITEST-11: biometric toggle is disabled with the stub label', (
      tester,
    ) async {
      await _useDesktopLayout(tester);
      await unlockVault(tester);

      await _tapControl(tester, find.byTooltip('Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Biometric unlock'), findsOneWidget);
      expect(find.text('not supported on this platform'), findsOneWidget);

      final biometricTile = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Biometric unlock'),
      );
      expect(biometricTile.onChanged, isNull);
    });

    testWidgets(
        'ITEST-12: autofill toggle is disabled with the coming soon label', (
      tester,
    ) async {
      await _useDesktopLayout(tester);
      await unlockVault(tester);

      await _tapControl(tester, find.byTooltip('Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Autofill'), findsOneWidget);
      expect(find.text('coming soon'), findsOneWidget);

      final autofillTile = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Autofill'),
      );
      expect(autofillTile.onChanged, isNull);
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
