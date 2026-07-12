import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:manyui/manyui.dart';
import 'package:keepass_ui/keepass_ui.dart' show VaultEntry, VaultGroup;
import 'package:manykee/src/app.dart';
import 'package:manykee/src/state/manykee_vault_state.dart';
import 'package:manykee/src/state/unlock_error_mapper.dart';
import 'package:manykee/src/state/vault_state_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _securityScopedFilesChannel = MethodChannel(
  'com.manykee.native/security_scoped_files',
);

/// In-memory vault state: no native library, no file system.
///
/// Accepts [acceptedPassword]; any other password maps a wrong-password
/// error exactly like the native implementation does.
class FakeVaultState extends ManyKeeVaultState {
  @override
  Future<List<Map<String, dynamic>>> listYubiKeys() async => yubiKeys;

  FakeVaultState({
    this.acceptedPassword = 'correct',
    this.yubiKeys = const <Map<String, dynamic>>[],
    this.creationSupported = true,
    this.mergeSupported = true,
    this.entryFields = const <String, dynamic>{
      'Title': 'Example',
      'UserName': 'alice',
      'URL': '',
      'Notes': '',
    },
    this.entryFieldValues = const <String, String>{'Password': 'hunter2'},
    this.entryFieldReadError,
    this.entryFieldLoader,
    this.selectGroupLoader,
    this.unlockGate,
    this.totp,
    this.searchableEntries = const <VaultEntry>[],
    this.initialGroups,
    this.initialEntries,
    String? initialFilePath,
  }) : _lastFilePath = initialFilePath;

  final String acceptedPassword;
  final List<Map<String, dynamic>> yubiKeys;
  final bool creationSupported;
  final bool mergeSupported;
  final Map<String, dynamic> entryFields;
  final Map<String, String> entryFieldValues;
  final Object? entryFieldReadError;
  final Future<String?> Function(String entryUuid, String fieldName)?
  entryFieldLoader;
  final Future<void> Function(VaultGroup group)? selectGroupLoader;
  final Future<void>? unlockGate;
  final Map<String, dynamic>? totp;
  final List<VaultEntry> searchableEntries;
  final List<VaultGroup>? initialGroups;
  final List<VaultEntry>? initialEntries;
  String? _lastFilePath;
  String? _lastYubiKeySlot;
  String? lastUnlockFilePath;
  String? lastUnlockPassword;
  String? lastUnlockKeyFilePath;
  String? lastUnlockFilename;
  String? createdDatabasePath;
  String? createdDatabasePassword;
  String? createdDatabaseFilename;
  final List<String> savedPasswords = <String>[];
  final List<String> copiedDatabasePaths = <String>[];
  final List<String> copiedDatabasePasswords = <String>[];
  Object? saveError;
  final List<Map<String, String?>> updatedEntryFields =
      <Map<String, String?>>[];
  final List<Set<String>> updatedProtectedFields = <Set<String>>[];
  bool disposed = false;

  @override
  bool get supportsDatabaseCreation => creationSupported;

  @override
  bool get supportsDatabaseMerge => mergeSupported;

  @override
  bool get allEntriesCached => true;

  @override
  List<VaultEntry> get searchResults {
    final query = searchQuery.trim().toLowerCase();
    if (query.isEmpty) return const <VaultEntry>[];
    final source = searchableEntries.isEmpty ? entries : searchableEntries;
    return source
        .where(
          (entry) => <String>[
            if (!entry.titleProtected) entry.title,
            if (!entry.usernameProtected) entry.username,
            if (!entry.urlProtected) entry.url,
            entry.breadcrumb ?? '',
          ].any((value) => value.toLowerCase().contains(query)),
        )
        .toList(growable: false);
  }

  @override
  String? get lastFilePath => _lastFilePath;

  @override
  String? get lastYubiKeySlot => _lastYubiKeySlot;

  @override
  Stream<int> get progress => const Stream<int>.empty();

  @override
  Future<void> unlock({
    Uint8List? dbBytes,
    String? filePath,
    required String password,
    Uint8List? keyFileBytes,
    String? challengeResponseHex,
    String? filename,
  }) {
    return unlockFromPath(filePath: filePath!, password: password);
  }

  @override
  Future<void> unlockFromPath({
    required String filePath,
    required String password,
    String? keyFilePath,
    String? filename,
    String? yubiKeySlot,
  }) async {
    await unlockGate;
    clearError();
    lastUnlockFilePath = filePath;
    lastUnlockPassword = password;
    lastUnlockKeyFilePath = keyFilePath;
    lastUnlockFilename = filename;
    if (password != acceptedPassword) {
      final mapped = mapUnlockError(
        'invalid credentials or corrupt database',
        filePath: filePath,
      );
      setErrorWithDetail(mapped.code, mapped.message, detail: mapped.detail);
      return;
    }
    _lastFilePath = filePath;
    _lastYubiKeySlot = yubiKeySlot;
    handleValue = 1;
    lastFilenameValue = filename ?? filePath;
    groupsValue =
        initialGroups ?? <VaultGroup>[VaultGroup(uuid: 'g1', name: 'General')];
    selectedGroupValue = groups.first;
    entriesValue =
        initialEntries ??
        <VaultEntry>[
          VaultEntry(
            uuid: 'e1',
            title: 'Example',
            username: 'alice',
            url: '',
            groupUuid: groups.first.uuid,
          ),
        ];
    isLockedValue = false;
    notifyListeners();
  }

  @override
  Future<void> createDatabaseAtPath({
    required String filePath,
    required String password,
    String? filename,
  }) async {
    clearError();
    createdDatabasePath = filePath;
    createdDatabasePassword = password;
    createdDatabaseFilename = filename;
    _lastFilePath = filePath;
    handleValue = 1;
    lastFilenameValue = filename ?? filePath;
    groupsValue = const <VaultGroup>[];
    entriesValue = const <VaultEntry>[];
    selectedGroupValue = null;
    selectedEntryValue = null;
    isLockedValue = false;
    notifyListeners();
  }

  void makeDirty() {
    markDirty();
  }

  @override
  Future<List<int>> saveDatabase({
    required String password,
    List<int>? keyFileBytes,
  }) async {
    savedPasswords.add(password);
    final error = saveError;
    if (error != null) {
      throw error;
    }
    clearDirtyFlag();
    return const <int>[];
  }

  @override
  Future<void> saveCopyAs({
    required String filePath,
    required String password,
  }) async {
    copiedDatabasePaths.add(filePath);
    copiedDatabasePasswords.add(password);
    final error = saveError;
    if (error != null) {
      throw error;
    }
  }

  @override
  void openDifferentFile() {
    _lastFilePath = null;
    lastFilenameValue = null;
    clearError();
    notifyListeners();
  }

  @override
  Future<void> lock() async {
    resetBrowsingState();
  }

  @override
  Future<void> selectGroup(VaultGroup group) async {
    final generation = beginGroupSelection();
    await selectGroupLoader?.call(group);
    if (!isCurrentGroupSelection(generation)) return;
    selectedGroupValue = group;
    notifyListeners();
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }

  @override
  Future<void> selectRoot() async {
    selectedGroupValue = null;
    selectedEntryValue = null;
    notifyListeners();
  }

  @override
  Future<Map<String, dynamic>> readEntryFields(String entryUuid) async {
    return Map<String, dynamic>.of(entryFields);
  }

  @override
  Future<String?> readEntryField(String entryUuid, String fieldName) async {
    final error = entryFieldReadError;
    if (error != null) throw error;
    final loader = entryFieldLoader;
    if (loader != null) return loader(entryUuid, fieldName);
    return entryFieldValues[fieldName];
  }

  @override
  Future<Map<String, dynamic>?> getTotpCode(String entryUuid) async =>
      totp == null ? null : Map<String, dynamic>.of(totp!);

  @override
  Future<void> updateEntry(
    String entryUuid,
    Map<String, String?> fields, {
    Set<String> protectedFields = const <String>{},
  }) async {
    updatedEntryFields.add(Map<String, String?>.of(fields));
    updatedProtectedFields.add(Set<String>.of(protectedFields));
    markDirty();
  }
}

class _FakeFilePicker extends FilePicker {
  _FakeFilePicker({this.savePath, List<PlatformFile>? pickFiles})
    : _pickFiles = pickFiles ?? const <PlatformFile>[];

  final String? savePath;
  final List<PlatformFile> _pickFiles;
  int _pickIndex = 0;

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
    bool readSequential = false,
    bool lockParentWindow = false,
  }) async {
    if (_pickIndex >= _pickFiles.length) return null;
    return FilePickerResult(<PlatformFile>[_pickFiles[_pickIndex++]]);
  }

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    return savePath;
  }
}

Widget appWith(FakeVaultState state) {
  return ProviderScope(
    overrides: <Override>[vaultStateProvider.overrideWith((ref) => state)],
    child: const ManyKeeApp(),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_securityScopedFilesChannel, null);
  });

  testWidgets('fresh unlock form renders', (tester) async {
    await tester.pumpWidget(appWith(FakeVaultState()));

    expect(find.text('Unlock a database'), findsOneWidget);
    expect(find.text('Choose file…'), findsOneWidget);
    expect(find.text('Unlock'), findsOneWidget);

    // YubiKey detection resolves to the empty list: the affordance row
    // stays visible with a re-detect action.
    await tester.pump();
    expect(find.text('No YubiKey detected.'), findsOneWidget);
    expect(find.text('Re-detect'), findsOneWidget);
  });

  testWidgets('database creation is hidden when the platform cannot save it', (
    tester,
  ) async {
    await tester.pumpWidget(appWith(FakeVaultState(creationSupported: false)));

    expect(find.text('Create new database…'), findsNothing);
    expect(find.text('Choose file…'), findsOneWidget);
  });

  testWidgets('re-unlock view shows path and maps a wrong password error', (
    tester,
  ) async {
    final state = FakeVaultState(initialFilePath: '/tmp/vault.kdbx');
    await tester.pumpWidget(appWith(state));

    expect(find.text('Vault locked'), findsOneWidget);
    expect(find.text('/tmp/vault.kdbx'), findsOneWidget);

    await tester.tap(find.byType(MTextField));
    await tester.pump();
    await tester.enterText(find.byType(EditableText), 'wrong-password');
    await tester.pump();
    await tester.tap(find.text('Unlock'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Incorrect password. Please try again.'), findsOneWidget);
    // Backend detail is retained in state for diagnostics, but not disclosed
    // as primary UI copy on the unlock surface.
    expect(find.text('invalid credentials or corrupt database'), findsNothing);
    expect(state.isLocked, isTrue);
  });

  testWidgets('re-unlock can retry after a wrong password', (tester) async {
    final state = FakeVaultState(initialFilePath: '/tmp/vault.kdbx');
    await tester.pumpWidget(appWith(state));

    await tester.tap(find.byType(MTextField));
    await tester.pump();
    await tester.enterText(find.byType(EditableText), 'wrong-password');
    await tester.pump();
    await tester.tap(find.text('Unlock'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Incorrect password. Please try again.'), findsOneWidget);
    expect(state.isLocked, isTrue);

    await tester.enterText(find.byType(EditableText), 'correct');
    await tester.pump();

    final retry = find.widgetWithText(MButton, 'Unlock');
    expect(tester.widget<MButton>(retry).onPressed, isNotNull);
    await tester.tap(retry);
    await tester.pump();
    await tester.pump();

    expect(state.lastUnlockPassword, 'correct');
    expect(state.isLocked, isFalse);
    expect(find.text('Lock'), findsOneWidget);
  });

  testWidgets('unlock page does NOT expose a merge-databases entry point '
      '(gated to an already-open vault, see vault_page_test.dart)', (
    tester,
  ) async {
    await tester.pumpWidget(appWith(FakeVaultState()));
    expect(find.text('Merge databases…'), findsNothing);
  });

  testWidgets('recent databases render in an inset list', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'manykee.recentDatabases':
          '[{"path":"/tmp/one.kdbx","label":"one.kdbx",'
          '"lastOpened":"2026-01-01T00:00:00.000"}]',
    });
    await tester.pumpWidget(appWith(FakeVaultState()));
    await tester.pump();
    await tester.pump();

    final inset = find.byType(MInsetPanel);
    expect(inset, findsOneWidget);
    expect(
      find.descendant(of: inset, matching: find.text('one.kdbx')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: inset, matching: find.byType(MListTile)),
      findsOneWidget,
    );
  });

  testWidgets('recent database unlock resolves a macOS security bookmark', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final methodCalls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_securityScopedFilesChannel, (call) async {
          methodCalls.add(call.method);
          switch (call.method) {
            case 'startAccessingBookmark':
              expect(call.arguments, <String, Object?>{
                'bookmark': 'bookmark-data',
              });
              return <String, Object?>{
                'token': 'access-token',
                'path': '/resolved/one.kdbx',
                'stale': false,
              };
            case 'stopAccessing':
              return null;
          }
          fail('Unexpected method ${call.method}');
        });

    SharedPreferences.setMockInitialValues(<String, Object>{
      'manykee.recentDatabases':
          '[{"path":"/tmp/one.kdbx","label":"one.kdbx",'
          '"lastOpened":"2026-01-01T00:00:00.000",'
          '"securityScopedBookmark":"bookmark-data"}]',
    });
    final state = FakeVaultState();
    await tester.pumpWidget(appWith(state));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('one.kdbx'));
    await tester.pump();
    await tester.enterText(find.byType(EditableText), 'correct');
    await tester.pump();
    await tester.ensureVisible(find.text('Unlock'));
    await tester.pump();
    await tester.tap(find.text('Unlock'));
    await tester.pump();
    await tester.pump();

    expect(methodCalls, <String>['startAccessingBookmark']);
    expect(state.lastUnlockFilePath, '/resolved/one.kdbx');
    expect(state.isLocked, isFalse);
    final prefs = await SharedPreferences.getInstance();
    final persisted = prefs.getString('manykee.recentDatabases');
    expect(persisted, contains('/resolved/one.kdbx'));
    expect(persisted, isNot(contains('/tmp/one.kdbx')));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('expired recent database bookmark leaves unlock retryable', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_securityScopedFilesChannel, (call) async {
          if (call.method == 'startAccessingBookmark') {
            throw PlatformException(
              code: 'RESOLVE_FAILED',
              message: 'Bookmark is stale.',
            );
          }
          fail('Unexpected method ${call.method}');
        });

    SharedPreferences.setMockInitialValues(<String, Object>{
      'manykee.recentDatabases':
          '[{"path":"/tmp/one.kdbx","label":"one.kdbx",'
          '"lastOpened":"2026-01-01T00:00:00.000",'
          '"securityScopedBookmark":"bookmark-data"}]',
    });
    final state = FakeVaultState();
    await tester.pumpWidget(appWith(state));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('one.kdbx'));
    await tester.pump();
    await tester.enterText(find.byType(EditableText), 'correct');
    await tester.pump();
    await tester.ensureVisible(find.text('Unlock'));
    await tester.pump();
    await tester.tap(find.text('Unlock'));
    await tester.pump();
    await tester.pump();

    expect(
      find.text('ManyKee no longer has permission to open this file.'),
      findsOneWidget,
    );
    final retry = find.widgetWithText(MButton, 'Unlock');
    expect(tester.widget<MButton>(retry).onPressed, isNotNull);
    expect(state.lastUnlockFilePath, isNull);
    expect(state.isLocked, isTrue);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('failed unlock after unmount still stops security access', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final gate = Completer<void>();
    final methodCalls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_securityScopedFilesChannel, (call) async {
          methodCalls.add(call.method);
          if (call.method == 'startAccessingBookmark') {
            return <String, Object?>{
              'token': 'access-token',
              'path': '/resolved/one.kdbx',
              'stale': false,
            };
          }
          if (call.method == 'stopAccessing') return null;
          fail('Unexpected method ${call.method}');
        });
    SharedPreferences.setMockInitialValues(<String, Object>{
      'manykee.recentDatabases':
          '[{"path":"/tmp/one.kdbx","label":"one.kdbx",'
          '"lastOpened":"2026-01-01T00:00:00.000",'
          '"securityScopedBookmark":"bookmark-data"}]',
    });
    final state = FakeVaultState(
      acceptedPassword: 'different',
      unlockGate: gate.future,
    );
    final overrides = <Override>[
      vaultStateProvider.overrideWith((ref) => state),
    ];
    await tester.pumpWidget(
      ProviderScope(overrides: overrides, child: const ManyKeeApp()),
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('one.kdbx'));
    await tester.pump();
    await tester.enterText(find.byType(EditableText), 'correct');
    await tester.ensureVisible(find.text('Unlock'));
    await tester.pump();
    await tester.tap(find.text('Unlock'));
    await tester.pump();
    expect(methodCalls, <String>['startAccessingBookmark']);

    await tester.pumpWidget(
      ProviderScope(overrides: overrides, child: const SizedBox()),
    );
    gate.complete();
    await tester.pump();

    expect(methodCalls, <String>['startAccessingBookmark', 'stopAccessing']);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('successful unlock opens the vault browser', (tester) async {
    final state = FakeVaultState(initialFilePath: '/tmp/vault.kdbx');
    await tester.pumpWidget(appWith(state));

    await tester.tap(find.byType(MTextField));
    await tester.pump();
    await tester.enterText(find.byType(EditableText), 'correct');
    await tester.pump();
    await tester.tap(find.text('Unlock'));
    await tester.pump();
    await tester.pump();

    expect(state.isLocked, isFalse);
    expect(find.text('Lock'), findsOneWidget);
    expect(find.text('General'), findsWidgets);

    // Default test surface is 800x600, so the tablet layout presents the
    // group tree and selected group's entries side by side.
    await tester.tap(
      find.descendant(
        of: find.byType(MTreeListTile),
        matching: find.text('General'),
      ),
    );
    await tester.pump();
    expect(find.text('Example'), findsOneWidget);
  });

  testWidgets('unlock can combine key file and YubiKey credentials', (
    tester,
  ) async {
    FilePicker.platform = _FakeFilePicker(
      pickFiles: <PlatformFile>[
        PlatformFile(name: 'vault.kdbx', path: '/tmp/vault.kdbx', size: 0),
        PlatformFile(name: 'vault.keyx', path: '/tmp/vault.keyx', size: 0),
      ],
    );
    addTearDown(() => FilePicker.platform = _FakeFilePicker());

    final state = FakeVaultState(
      yubiKeys: const <Map<String, dynamic>>[
        <String, dynamic>{'serial_number': 123456, 'name': 'YubiKey'},
      ],
    );
    await tester.pumpWidget(appWith(state));
    await tester.pump();

    await tester.tap(find.text('Choose file…'));
    await tester.pump();
    await tester.tap(find.text('Choose key file…'));
    await tester.pump();
    await tester.enterText(find.byType(EditableText), 'correct');
    await tester.pump();
    await tester.tap(find.byType(MCheckbox));
    await tester.pump();
    await tester.ensureVisible(find.text('Unlock'));
    await tester.pump();
    await tester.tap(find.text('Unlock'));
    await tester.pump();
    await tester.pump();

    expect(state.isLocked, isFalse);
    expect(state.lastUnlockFilePath, '/tmp/vault.kdbx');
    expect(state.lastUnlockKeyFilePath, '/tmp/vault.keyx');
    expect(state.lastUnlockFilename, 'vault.kdbx');
    expect(state.lastYubiKeySlot, '2');
  });

  testWidgets('create new database saves and opens the new vault', (
    tester,
  ) async {
    FilePicker.platform = _FakeFilePicker(savePath: '/tmp/fresh-vault');
    addTearDown(() => FilePicker.platform = _FakeFilePicker());

    final state = FakeVaultState();
    await tester.pumpWidget(appWith(state));

    await tester.tap(find.text('Create new database…'));
    await tester.pump();

    expect(find.text('Create database'), findsOneWidget);

    final dialogFields = find.descendant(
      of: find.byType(MDialog),
      matching: find.byType(EditableText),
    );
    expect(dialogFields, findsNWidgets(2));

    await tester.enterText(dialogFields.at(0), 'fresh-pass');
    await tester.pump();
    await tester.enterText(dialogFields.at(1), 'different');
    await tester.pump();
    expect(find.text('Passwords do not match.'), findsOneWidget);

    await tester.enterText(dialogFields.at(1), 'fresh-pass');
    await tester.pump();
    await tester.tap(
      find.descendant(of: find.byType(MDialog), matching: find.text('Create')),
    );
    await tester.pump();
    await tester.pump();

    expect(state.createdDatabasePath, '/tmp/fresh-vault.kdbx');
    expect(state.createdDatabasePassword, 'fresh-pass');
    expect(state.createdDatabaseFilename, 'fresh-vault.kdbx');
    expect(state.isLocked, isFalse);
    expect(find.text('Lock'), findsOneWidget);
    expect(find.text('Vault root'), findsWidgets);
    expect(find.bySemanticsLabel('New entry'), findsWidgets);
  });
}
