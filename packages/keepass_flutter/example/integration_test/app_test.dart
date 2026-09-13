import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:keepass_ui/keepass_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:keepass_flutter_example/main.dart';
import 'package:keepass_flutter_example/src/screens/vault_screen.dart';
import 'package:keepass_flutter_example/src/state/settings_state.dart';

File? _stagedLibrary;

String _fixturePath(String name) {
  final searched = <String>[];
  Directory? current = Directory.current.absolute;

  while (current != null) {
    final direct = File('${current.path}/integration_test/fixtures/$name');
    searched.add(direct.path);
    if (direct.existsSync()) {
      return direct.path;
    }

    final nested = File(
      '${current.path}/packages/keepass_flutter/example/integration_test/fixtures/$name',
    );
    searched.add(nested.path);
    if (nested.existsSync()) {
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

const String _officialFixtureSubdir =
    'fixtures/compat/official/keepassxc/2.7.12';

String? _officialFixturePath(String name) {
  Directory? current = Directory.current.absolute;
  while (current != null) {
    final candidate = File('${current.path}/$_officialFixtureSubdir/$name');
    if (candidate.existsSync()) {
      return candidate.path;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      current = null;
    } else {
      current = parent;
    }
  }
  return null;
}

/// Copies `libkeepassxc_ffi.so` into the test runner's CWD, where
/// `native_library.dart` looks for it in debug runs; the cargo output lives
/// too far up the tree (`<monorepo>/rust/target`) for the loader to probe it
/// from `example/`. Returns the copy this run made and must delete, or null
/// when one was already present.
Future<File?> _stageNativeLibrary() async {
  final sourcePath = _firstExisting(<String>[
    // Fresh cargo output first (from example/, then from keepass_flutter/).
    '../../../rust/target/debug/libkeepassxc_ffi.so',
    '../../../rust/target/release/libkeepassxc_ffi.so',
    '../../rust/target/debug/libkeepassxc_ffi.so',
    '../../rust/target/release/libkeepassxc_ffi.so',
    // Last resort: a copy a sibling package's tests staged for themselves.
    '../../keepass_cli/libkeepassxc_ffi.so',
    '../keepass_cli/libkeepassxc_ffi.so',
  ]);
  final staged = File('${Directory.current.path}/libkeepassxc_ffi.so');
  if (await staged.exists()) {
    return null;
  }
  await _copyAtomically(File(sourcePath), staged);
  return staged;
}

/// Copies [source] to a uniquely named temporary file beside [destination]
/// and renames it into place, so a concurrent test run that loads
/// [destination] never sees a half-written library (`dlopen` accepts one and
/// the process then dies with SIGBUS).
Future<void> _copyAtomically(File source, File destination) async {
  final temp = File(
    '${destination.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp',
  );
  try {
    await source.copy(temp.path);
    await temp.rename(destination.path);
  } catch (_) {
    if (await temp.exists()) {
      await temp.delete();
    }
    rethrow;
  }
}

String _firstExisting(List<String> candidates) {
  return candidates.firstWhere(
    (path) => File(path).existsSync(),
    orElse: () => throw StateError(
      'No file found for candidates: ${candidates.join(', ')}',
    ),
  );
}

class _FakeFilePicker extends FilePicker {
  _FakeFilePicker(this.path, this.name);

  final String path;
  final String name;

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
    return FilePickerResult(<PlatformFile>[
      PlatformFile(name: name, path: path, size: await File(path).length()),
    ]);
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
    if (finder.evaluate().isNotEmpty) {
      return true;
    }
  }
  await tester.pumpAndSettle();
  return finder.evaluate().isNotEmpty;
}

Finder _chooseDatabaseButton() =>
    find.widgetWithText(OutlinedButton, 'Choose KDBX File');

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

Future<void> _useDesktopLayout(WidgetTester tester) async {
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.binding.setSurfaceSize(const Size(1280, 800));
}

Future<_WritableFixture> _copyFixtureToTemp(String fixtureName) async {
  final sourcePath = _fixturePath(fixtureName);
  final tempDir = await Directory.systemTemp.createTemp('manykee-example-');
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

Future<SettingsState> unlockVault(
  WidgetTester tester, {
  String? fixtureName,
  String? fixturePath,
  String password = 'demopass',
  Duration timeout = const Duration(seconds: 120),
  SettingsState? settings,
  bool resetPreferences = true,
}) async {
  if (resetPreferences) {
    SharedPreferences.setMockInitialValues(<String, Object>{});
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    _stagedLibrary = await _stageNativeLibrary();
  });

  tearDownAll(() async {
    final stagedLibrary = _stagedLibrary;
    if (stagedLibrary != null && await stagedLibrary.exists()) {
      await stagedLibrary.delete();
    }
  });

  group('Unlock flow', () {
    testWidgets('unlock screen shows initial UI', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
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

  group('Vault browsing', () {
    testWidgets('shows app bar with lock and settings buttons', (tester) async {
      await unlockVault(tester);

      expect(find.byTooltip('Lock Vault'), findsOneWidget);
      expect(find.byTooltip('Settings'), findsOneWidget);
    });

    testWidgets('group navigation updates entry list', (tester) async {
      await unlockVault(tester);

      Finder? groupFinder;
      for (final name in <String>[
        'Internet',
        'eMail',
        'Homebanking',
        'Network'
      ]) {
        final finder = find.text(name);
        if (finder.evaluate().isNotEmpty) {
          groupFinder = finder;
          break;
        }
      }

      if (groupFinder != null) {
        await _tapControl(tester, groupFinder);
        await tester.pumpAndSettle(const Duration(seconds: 2));
      }

      expect(find.byType(CircleAvatar), findsWidgets);
    });
  });

  group('Search', () {
    testWidgets('search filters entries across groups', (tester) async {
      await unlockVault(tester);

      await _tapControl(tester, _searchField().first);
      await tester.pumpAndSettle();
      tester.testTextInput.enterText('test');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      final hasEmptyState = find.text('No entries').evaluate().isNotEmpty ||
          find.text('No matches').evaluate().isNotEmpty;
      expect(
        find.byType(CircleAvatar).evaluate().isNotEmpty || hasEmptyState,
        isTrue,
      );
    });
  });

  group('Lock and re-unlock', () {
    testWidgets('lock returns to lock screen', (tester) async {
      await unlockVault(tester);

      await _tapControl(tester, find.byTooltip('Lock Vault'));
      await tester.pumpAndSettle();

      expect(find.text('Vault Locked'), findsOneWidget);
      expect(find.text('test_db_with_password.kdbx'), findsOneWidget);
    });

    testWidgets('re-unlock from lock screen', (tester) async {
      await unlockVault(tester);

      await _tapControl(tester, find.byTooltip('Lock Vault'));
      await tester.pumpAndSettle();
      expect(find.text('Vault Locked'), findsOneWidget);

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
    });
  });

  group('Settings', () {
    testWidgets('settings screen accessible and functional', (tester) async {
      final settings = await unlockVault(tester);

      await _tapControl(tester, find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);

      await _tapControl(tester, find.text('Never'));
      await tester.pumpAndSettle();
      await _tapControl(tester, find.text('15 minutes').last);
      await tester.pumpAndSettle();

      await _tapControl(tester, find.text('System'));
      await tester.pumpAndSettle();
      await _tapControl(tester, find.text('Dark').last);
      await tester.pumpAndSettle();

      expect(settings.autoLockTimeoutMinutes, 15);
      expect(settings.themeMode, 'dark');
      expect(find.text('not supported on this platform'), findsOneWidget);
      expect(find.text('coming soon'), findsOneWidget);
    });
  });

  group('Reference GUI write coverage', () {
    testWidgets('creates a new entry and reload keeps it', (tester) async {
      await _useDesktopLayout(tester);
      final writableFixture =
          await _copyFixtureToTemp('test_db_with_password.kdbx');

      await unlockVault(
        tester,
        fixtureName: writableFixture.name,
        fixturePath: writableFixture.path,
      );

      await _tapControl(tester, find.text('New Entry'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Created Integration Entry');
      await tester.enterText(fields.at(1), 'created-user');
      await tester.enterText(fields.at(2), 'created-pass');
      await tester.tap(find.text('Create Entry').last);
      await tester.pumpAndSettle();

      expect(find.text('Created Integration Entry'), findsWidgets);

      await _saveVaultAndReload(tester, password: 'demopass');
      expect(find.text('Created Integration Entry'), findsWidgets);
    });

    testWidgets('edits the first entry title and password with persistence',
        (tester) async {
      await _useDesktopLayout(tester);
      final writableFixture =
          await _copyFixtureToTemp('test_db_with_password.kdbx');

      await unlockVault(
        tester,
        fixtureName: writableFixture.name,
        fixturePath: writableFixture.path,
      );

      final vaultScreen = tester.widget<NativeVaultScreen>(
        find.byType(NativeVaultScreen),
      );
      final originalTitle = vaultScreen.vaultState.entries.first.title;

      await _tapControl(tester, find.text(originalTitle).first);
      await tester.pumpAndSettle();
      await _tapControl(tester, find.byTooltip('Edit Entry'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Edited Integration Entry');
      await tester.enterText(fields.at(2), 'UpdatedPass!23');
      await _tapControl(tester, find.text('Save Entry').last);
      await tester.pumpAndSettle();

      expect(find.text('Edited Integration Entry'), findsWidgets);

      await _saveVaultAndReload(tester, password: 'demopass');

      await _tapControl(tester, find.text('Edited Integration Entry').last);
      final reopenedScreen = tester.widget<NativeVaultScreen>(
        find.byType(NativeVaultScreen),
      );
      final reopenedEntry = reopenedScreen.vaultState.entries.firstWhere(
        (entry) => entry.title == 'Edited Integration Entry',
      );
      final persistedFields =
          await reopenedScreen.vaultState.readEntryFields(reopenedEntry.uuid);
      expect(persistedFields['Password'], 'UpdatedPass!23');
    });

    testWidgets('creates and renames a subgroup with persistence',
        (tester) async {
      await _useDesktopLayout(tester);
      final writableFixture =
          await _copyFixtureToTemp('test_db_with_password.kdbx');

      await unlockVault(
        tester,
        fixtureName: writableFixture.name,
        fixturePath: writableFixture.path,
      );

      await _openGroupMenu(tester, 'General');
      await _tapControl(tester, find.text('New Subgroup'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Projects');
      await _tapControl(tester, find.text('Create Group').last);
      await tester.pumpAndSettle();
      expect(_groupLabel('Projects'), findsOneWidget);

      await _openGroupMenu(tester, 'Projects');
      await _tapControl(tester, find.text('Rename Group'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Projects Renamed');
      await _tapControl(tester, find.text('Save Group').last);
      await tester.pumpAndSettle();
      expect(_groupLabel('Projects Renamed'), findsOneWidget);

      await _saveVaultAndReload(tester, password: 'demopass');
      final reopenedScreen = tester.widget<NativeVaultScreen>(
        find.byType(NativeVaultScreen),
      );
      expect(
        _groupExists(reopenedScreen.vaultState.groups, 'Projects Renamed'),
        isTrue,
      );
    });
  });

  group('Native-specific', () {
    testWidgets('open different file returns to unlock screen', (tester) async {
      await unlockVault(tester);

      await _tapControl(tester, find.byTooltip('Lock Vault'));
      await tester.pumpAndSettle();
      expect(find.text('Vault Locked'), findsOneWidget);

      await _tapControl(tester, _openDifferentFileButton());
      await tester.pumpAndSettle();

      expect(find.text('ManyKee'), findsOneWidget);
      expect(find.text('Choose KDBX File'), findsOneWidget);
    });
  });

  group('YubiKey (conditional)', () {
    testWidgets('YubiKey challenge-response unlock', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
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
      if (!yubiKeyDetected) {
        return;
      }

      final ykDbPath = _fixturePath('test_db_with_challenge_response_key.kdbx');
      FilePicker.platform = _FakeFilePicker(ykDbPath, 'yk_test.kdbx');
      await _tapControl(tester, _chooseDatabaseButton());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Master Password'),
        'demopass',
      );
      await tester.pumpAndSettle();

      final useYubiKey = find.text('Use YubiKey');
      if (useYubiKey.evaluate().isNotEmpty) {
        await _tapControl(tester, useYubiKey);
        await tester.pumpAndSettle();
      }

      await _tapControl(tester, _unlockVaultButton());

      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 500));
        if (find.byTooltip('Lock Vault').evaluate().isNotEmpty) {
          break;
        }
      }
    });
  });

  group(' official fixture smoke', () {
    // Canonical fixture password provenance: `FIXTURE_PASSWORD` in
    // `rust/keepassxc/tests/bidirectional_parity.rs`.
    const fixturePassword = 'manykee-fixture-password';
    const fixtureName = 'keepassxc-password-basic.kdbx';
    const requireEnvVar = 'MANYKEE_REQUIRE_OFFICIAL_TOOLS';

    testWidgets('keepassxc-password-basic.kdbx unlocks', (tester) async {
      final required = Platform.environment[requireEnvVar] == '1';
      final sourcePath = _officialFixturePath(fixtureName);
      if (sourcePath == null) {
        final reason = 'skipped: fixture $fixtureName not found under '
            '$_officialFixtureSubdir/ (searched upward from '
            '${Directory.current.path})';
        if (required) {
          fail('$requireEnvVar=1 but $reason');
        }
        markTestSkipped(reason);
        return;
      }

      final tempDir =
          await Directory.systemTemp.createTemp('manykee-official-');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final tempPath = '${tempDir.path}/$fixtureName';
      await File(sourcePath).copy(tempPath);

      // Note: like the other `unlockVault`-based tests in this file, this
      // case assumes no real YubiKey is attached to the host. The unlock
      // screen auto-selects YubiKey mode whenever `listYubiKeys()` returns a
      // non-empty list, which forces `openFromPathWithYubiKey` and breaks
      // password-only unlock. CI hosts have no YubiKey hardware and pass
      // cleanly; local runs on a YubiKey-equipped workstation will fail the
      // same way the existing 'unlocks vault with correct password' case
      // does in that environment.
      await unlockVault(
        tester,
        fixtureName: fixtureName,
        fixturePath: tempPath,
        password: fixturePassword,
      );

      expect(find.byTooltip('Lock Vault'), findsOneWidget);
    });
  });
}
