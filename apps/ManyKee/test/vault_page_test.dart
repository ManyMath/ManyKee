import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_ui/keepass_ui.dart' show VaultEntry, VaultGroup;
import 'package:manyui/manyui.dart';

import 'unlock_page_test.dart' show FakeVaultState, appWith;

void main() {
  testWidgets(
    'vault page exposes a merge-databases entry point once unlocked',
    (tester) async {
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
      await _openVaultActions(tester);
      expect(find.text('Merge databases…'), findsOneWidget);

      final button = tester.widget<MButton>(
        find.ancestor(
          of: find.text('Merge databases…'),
          matching: find.byType(MButton),
        ),
      );
      expect(
        button.onPressed,
        isNotNull,
        reason:
            'the button must be enabled once a vault with a known '
            'file path is open, not left disabled',
      );
    },
  );

  testWidgets('merge is hidden when the platform workflow is unsupported', (
    tester,
  ) async {
    final state = FakeVaultState(
      initialFilePath: '/tmp/vault.kdbx',
      mergeSupported: false,
    );
    await _unlockVault(tester, state);
    await _openVaultActions(tester);

    expect(find.text('Merge databases…'), findsNothing);
    expect(find.text('Save a copy…'), findsOneWidget);
  });

  testWidgets('dirty vault exposes save controls and saves with password', (
    tester,
  ) async {
    final state = FakeVaultState(initialFilePath: '/tmp/vault.kdbx');
    await _unlockVault(tester, state);

    state.makeDirty();
    await tester.pump();

    expect(find.text('Unsaved · auto-lock paused'), findsOneWidget);
    expect(find.widgetWithText(MButton, 'Save changes'), findsOneWidget);
    expect(find.bySemanticsLabel('Vault actions'), findsWidgets);

    await tester.tap(find.widgetWithText(MButton, 'Save changes'));
    await tester.pump();

    final passwordField = find.descendant(
      of: find.byType(MDialog),
      matching: find.byType(EditableText),
    );
    expect(passwordField, findsOneWidget);

    await tester.enterText(passwordField, 'save-pass');
    await tester.pump();
    await tester.tap(
      find.descendant(of: find.byType(MDialog), matching: find.text('Save')),
    );
    await tester.pump();
    await tester.pump();

    expect(state.savedPasswords, <String>['save-pass']);
    expect(state.isDirty, isFalse);
    expect(state.isLocked, isFalse);
    expect(find.text('Unsaved · auto-lock paused'), findsNothing);
  });

  testWidgets(
    'save a copy writes alternate path without clearing dirty state',
    (tester) async {
      FilePicker.platform = _FakeFilePicker(savePath: '/tmp/vault-copy');
      addTearDown(() => FilePicker.platform = _FakeFilePicker());

      final state = FakeVaultState(initialFilePath: '/tmp/vault.kdbx');
      await _unlockVault(tester, state);
      state.makeDirty();
      await tester.pump();

      await _openVaultActions(tester);
      await tester.tap(find.widgetWithText(MButton, 'Save a copy…'));
      await tester.pump();

      final passwordField = find.descendant(
        of: find.byType(MDialog),
        matching: find.byType(EditableText),
      );
      expect(passwordField, findsOneWidget);

      await tester.enterText(passwordField, 'copy-pass');
      await tester.pump();
      await tester.tap(
        find.descendant(of: find.byType(MDialog), matching: find.text('Save')),
      );
      await tester.pump();
      await tester.pump();

      expect(state.copiedDatabasePaths, <String>['/tmp/vault-copy.kdbx']);
      expect(state.copiedDatabasePasswords, <String>['copy-pass']);
      expect(state.lastFilePath, '/tmp/vault.kdbx');
      expect(state.isDirty, isTrue);
      expect(state.isLocked, isFalse);
    },
  );

  testWidgets('dirty lock can be cancelled without losing changes', (
    tester,
  ) async {
    final state = FakeVaultState(initialFilePath: '/tmp/vault.kdbx');
    await _unlockVault(tester, state);
    state.makeDirty();
    await tester.pump();

    await tester.tap(find.widgetWithText(MButton, 'Lock'));
    await tester.pump();

    expect(find.text('Unsaved changes'), findsWidgets);
    await tester.tap(
      find.descendant(of: find.byType(MDialog), matching: find.text('Cancel')),
    );
    await tester.pump();

    expect(state.isLocked, isFalse);
    expect(state.isDirty, isTrue);
    expect(find.widgetWithText(MButton, 'Lock'), findsOneWidget);
  });

  testWidgets('dirty lock can save first and then lock', (tester) async {
    final state = FakeVaultState(initialFilePath: '/tmp/vault.kdbx');
    await _unlockVault(tester, state);
    state.makeDirty();
    await tester.pump();

    await tester.tap(find.widgetWithText(MButton, 'Lock'));
    await tester.pump();
    await tester.tap(
      find.descendant(of: find.byType(MDialog), matching: find.text('Save')),
    );
    await tester.pump();

    final passwordField = find.descendant(
      of: find.byType(MDialog),
      matching: find.byType(EditableText),
    );
    await tester.enterText(passwordField, 'save-before-lock');
    await tester.pump();
    await tester.tap(
      find.descendant(of: find.byType(MDialog), matching: find.text('Save')),
    );
    await tester.pump();
    await tester.pump();

    expect(state.savedPasswords, <String>['save-before-lock']);
    expect(state.isLocked, isTrue);
    expect(state.isDirty, isFalse);
    expect(find.text('Vault locked'), findsOneWidget);
  });

  testWidgets('dirty discard confirms and locks without saving', (
    tester,
  ) async {
    final state = FakeVaultState(initialFilePath: '/tmp/vault.kdbx');
    await _unlockVault(tester, state);
    state.makeDirty();
    await tester.pump();

    await _openVaultActions(tester);
    await tester.tap(find.widgetWithText(MButton, 'Discard changes'));
    await tester.pump();

    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(
      find.descendant(of: find.byType(MDialog), matching: find.text('Discard')),
    );
    await tester.pump();
    await tester.pump();

    expect(state.savedPasswords, isEmpty);
    expect(state.isLocked, isTrue);
    expect(state.isDirty, isFalse);
    expect(find.text('Vault locked'), findsOneWidget);
  });

  testWidgets('editing a scrubbed entry preserves its protected password', (
    tester,
  ) async {
    final state = FakeVaultState(
      initialFilePath: '/tmp/vault.kdbx',
      entryFields: const <String, dynamic>{
        'Title': 'Example',
        'UserName': 'alice',
        'URL': 'https://example.test',
        'Notes': '',
        'protected': <String, bool>{'Password': true},
      },
    );
    await _unlockVault(tester, state);

    await tester.tap(find.text('Example'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Edit entry').first);
    await tester.pump();

    final formFields = find.descendant(
      of: find.byType(MDialog),
      matching: find.byType(EditableText),
    );
    await tester.enterText(formFields.first, 'Renamed example');
    await tester.pump();
    final saveEntry = find.descendant(
      of: find.byType(MDialog),
      matching: find.text('Save Entry'),
    );
    await tester.ensureVisible(saveEntry);
    await tester.tap(saveEntry);
    await tester.pump();

    expect(state.updatedEntryFields, hasLength(1));
    expect(state.updatedEntryFields.single['Title'], 'Renamed example');
    expect(
      state.updatedEntryFields.single,
      isNot(contains('Password')),
      reason: 'a scrubbed protected value must not be overwritten with empty',
    );
    expect(state.updatedProtectedFields.single, isEmpty);
  });

  testWidgets('editing omits every untouched scrubbed protected field', (
    tester,
  ) async {
    final state = FakeVaultState(
      initialFilePath: '/tmp/vault.kdbx',
      entryFields: const <String, dynamic>{
        'Title': 'Example',
        'UserName': '',
        'URL': 'https://example.test',
        'Notes': '',
        'protected': <String, bool>{
          'UserName': true,
          'Password': true,
          'Notes': true,
        },
      },
    );
    await _unlockVault(tester, state);

    await tester.tap(find.text('Example'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Edit entry').first);
    await tester.pump();
    final saveEntry = find.descendant(
      of: find.byType(MDialog),
      matching: find.text('Save Entry'),
    );
    await tester.ensureVisible(saveEntry);
    await tester.tap(saveEntry);
    await tester.pump();

    expect(
      state.updatedEntryFields.single,
      isNot(
        anyOf(contains('UserName'), contains('Password'), contains('Notes')),
      ),
    );
    expect(state.updatedProtectedFields.single, isEmpty);
  });

  testWidgets('replacing a scrubbed standard field keeps it protected', (
    tester,
  ) async {
    final state = FakeVaultState(
      initialFilePath: '/tmp/vault.kdbx',
      entryFields: const <String, dynamic>{
        'Title': 'Example',
        'UserName': '',
        'URL': '',
        'Notes': '',
        'protected': <String, bool>{
          'UserName': true,
          'Password': true,
          'Notes': true,
        },
      },
    );
    await _unlockVault(tester, state);

    await tester.tap(find.text('Example'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Edit entry').first);
    await tester.pump();
    final formFields = find.descendant(
      of: find.byType(MDialog),
      matching: find.byType(EditableText),
    );
    await tester.enterText(formFields.at(1), 'replacement-user');
    await tester.pump();
    final saveEntry = find.descendant(
      of: find.byType(MDialog),
      matching: find.text('Save Entry'),
    );
    await tester.ensureVisible(saveEntry);
    await tester.tap(saveEntry);
    await tester.pump();

    expect(state.updatedEntryFields.single['UserName'], 'replacement-user');
    expect(state.updatedEntryFields.single, isNot(contains('Password')));
    expect(state.updatedEntryFields.single, isNot(contains('Notes')));
    expect(state.updatedProtectedFields.single, const <String>{'UserName'});
  });

  testWidgets('editing does not preload native protected field values', (
    tester,
  ) async {
    final state = FakeVaultState(
      initialFilePath: '/tmp/vault.kdbx',
      entryFields: const <String, dynamic>{
        'Title': 'Example',
        'UserName': 'native-protected-user',
        'Password': 'native-protected-password',
        'URL': 'https://native-protected.example',
        'Notes': 'native protected notes',
        'protected': <String, bool>{
          'UserName': true,
          'Password': true,
          'URL': true,
          'Notes': true,
        },
      },
    );
    await _unlockVault(tester, state);

    await tester.tap(find.text('Example'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Edit entry').first);
    await tester.pump();

    final formFields = find.descendant(
      of: find.byType(MDialog),
      matching: find.byType(EditableText),
    );
    expect(
      tester
          .widgetList<EditableText>(formFields)
          .map((field) => field.controller.text),
      <String>['Example', '', '', '', ''],
    );
    expect(find.text('native-protected-user'), findsNothing);
    expect(find.text('native-protected-password'), findsNothing);
    expect(find.text('https://native-protected.example'), findsNothing);
    expect(find.text('native protected notes'), findsNothing);

    final saveEntry = find.descendant(
      of: find.byType(MDialog),
      matching: find.text('Save Entry'),
    );
    await tester.ensureVisible(saveEntry);
    await tester.tap(saveEntry);
    await tester.pump();

    expect(
      state.updatedEntryFields.single,
      isNot(
        anyOf(
          contains('UserName'),
          contains('Password'),
          contains('URL'),
          contains('Notes'),
        ),
      ),
    );
    expect(state.updatedProtectedFields.single, isEmpty);
  });

  testWidgets('secret read failures show feedback without leaking errors', (
    tester,
  ) async {
    final state = FakeVaultState(
      initialFilePath: '/tmp/vault.kdbx',
      entryFields: const <String, dynamic>{
        'Title': 'Example',
        'UserName': 'alice',
        'URL': '',
        'Notes': '',
        'protected': <String, bool>{'Password': true},
      },
      entryFieldReadError: StateError('backend unavailable'),
    );
    await _unlockVault(tester, state);

    await tester.tap(find.text('Example'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Reveal Password').first);
    await tester.pump();
    await tester.pump();

    expect(find.text('Password could not be read.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('entry detail shows TOTP, tags, and custom protected fields', (
    tester,
  ) async {
    final state = FakeVaultState(
      initialFilePath: '/tmp/vault.kdbx',
      entryFields: const <String, dynamic>{
        'Title': 'Example',
        'UserName': 'alice',
        'URL': 'https://example.test',
        'Notes': 'Recovery account',
        'Tags': 'work, admin',
        'Environment': 'Production',
        'API token': '',
        'protected': <String, bool>{'Password': true, 'API token': true},
      },
      entryFieldValues: const <String, String>{
        'Password': 'hunter2',
        'API token': 'secret-token',
      },
      totp: const <String, dynamic>{
        'code': '123456',
        'valid_for': 30,
        'period': 30,
      },
    );
    await _unlockVault(tester, state);

    await tester.tap(find.text('Example'));
    await tester.pump();
    await tester.pump();

    expect(find.text('123 456'), findsOneWidget);
    expect(find.text('Refreshes in 30s of 30s'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Production'),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Production'), findsOneWidget);
    expect(find.text('secret-token'), findsNothing);

    await tester.scrollUntilVisible(
      find.bySemanticsLabel('Reveal API token'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.bySemanticsLabel('Reveal API token').first);
    await tester.pump();
    expect(find.text('secret-token'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('admin'),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('work'), findsOneWidget);
    expect(find.text('admin'), findsOneWidget);
  });

  testWidgets('entry detail reveals protected standard fields on demand', (
    tester,
  ) async {
    final state = FakeVaultState(
      initialFilePath: '/tmp/vault.kdbx',
      entryFields: const <String, dynamic>{
        'Title': 'Example',
        'UserName': '',
        'URL': '',
        'Notes': '',
        'protected': <String, bool>{
          'UserName': true,
          'URL': true,
          'Notes': true,
        },
      },
      entryFieldValues: const <String, String>{
        'UserName': 'protected-user',
        'URL': 'https://protected.example',
        'Notes': 'protected notes',
      },
    );
    await _unlockVault(tester, state);

    await tester.tap(find.text('Example'));
    await tester.pump();
    await tester.pump();

    expect(find.text('protected-user'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Reveal UserName').first);
    await tester.pump();
    expect(find.text('protected-user'), findsOneWidget);
  });

  testWidgets('a delayed secret reveal cannot cross into another entry', (
    tester,
  ) async {
    final delayedSecret = Completer<String?>();
    final state = FakeVaultState(
      initialFilePath: '/tmp/vault.kdbx',
      initialEntries: <VaultEntry>[
        VaultEntry(
          uuid: 'e1',
          title: 'First entry',
          username: '',
          url: '',
          groupUuid: 'g1',
        ),
        VaultEntry(
          uuid: 'e2',
          title: 'Second entry',
          username: '',
          url: '',
          groupUuid: 'g1',
        ),
      ],
      entryFields: const <String, dynamic>{
        'Title': 'Entry detail',
        'UserName': '',
        'URL': '',
        'Notes': '',
        'protected': <String, bool>{'Password': true},
      },
      entryFieldLoader: (entryUuid, fieldName) {
        if (entryUuid == 'e1' && fieldName == 'Password') {
          return delayedSecret.future;
        }
        return Future<String?>.value('second-secret');
      },
    );
    await _unlockVault(tester, state);

    await tester.tap(find.text('First entry'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Reveal Password').first);
    await tester.pump();

    await tester.tap(find.text('Second entry'));
    await tester.pump();
    await tester.pump();
    delayedSecret.complete('first-entry-secret');
    await tester.pump();

    expect(state.selectedEntry?.uuid, 'e2');
    expect(find.text('first-entry-secret'), findsNothing);
  });

  testWidgets('vault-wide search shows matches with their group breadcrumb', (
    tester,
  ) async {
    final general = VaultGroup(uuid: 'g1', name: 'General');
    final infrastructure = VaultGroup(uuid: 'g2', name: 'Infrastructure');
    final state = FakeVaultState(
      initialFilePath: '/tmp/vault.kdbx',
      initialGroups: <VaultGroup>[general, infrastructure],
      searchableEntries: <VaultEntry>[
        VaultEntry(
          uuid: 'e1',
          title: 'Example',
          username: 'alice',
          url: '',
          groupUuid: 'g1',
          breadcrumb: 'General',
        ),
        VaultEntry(
          uuid: 'e2',
          title: 'Company VPN',
          username: 'alex',
          url: 'https://vpn.example.test',
          groupUuid: 'g2',
          breadcrumb: 'Work / Infrastructure',
        ),
        VaultEntry(
          uuid: 'e3',
          title: 'Protected VPN title',
          username: '',
          url: '',
          groupUuid: 'g2',
          breadcrumb: 'Protected',
          protectedFields: const <String>{'Title'},
        ),
      ],
    );
    await _unlockVault(tester, state);

    await tester.enterText(find.byType(EditableText).first, 'vpn');
    await tester.pump();

    expect(find.text('Search results'), findsOneWidget);
    expect(find.text('Company VPN'), findsOneWidget);
    expect(find.text('Protected entry'), findsNothing);
    expect(find.text('alex · Work / Infrastructure'), findsOneWidget);
    expect(find.text('Example'), findsNothing);

    await tester.tap(find.text('Company VPN'));
    await tester.pump();
    await tester.pump();

    expect(state.selectedGroup?.uuid, 'g2');
    expect(state.selectedEntry?.uuid, 'e2');
  });

  testWidgets('newer search navigation cancels a slower group selection', (
    tester,
  ) async {
    final delayedGroup = Completer<void>();
    final general = VaultGroup(uuid: 'g1', name: 'General');
    final infrastructure = VaultGroup(uuid: 'g2', name: 'Infrastructure');
    final state = FakeVaultState(
      initialFilePath: '/tmp/vault.kdbx',
      initialGroups: <VaultGroup>[general, infrastructure],
      searchableEntries: <VaultEntry>[
        VaultEntry(
          uuid: 'e1',
          title: 'First result',
          username: '',
          url: '',
          groupUuid: 'g1',
        ),
        VaultEntry(
          uuid: 'e2',
          title: 'Second result',
          username: '',
          url: '',
          groupUuid: 'g2',
        ),
      ],
      selectGroupLoader: (group) =>
          group.uuid == 'g2' ? delayedGroup.future : Future<void>.value(),
    );
    await _unlockVault(tester, state);
    await tester.enterText(find.byType(EditableText).first, 'result');
    await tester.pump();

    await tester.tap(find.text('Second result'));
    await tester.pump();
    await tester.tap(find.text('First result'));
    await tester.pump();
    delayedGroup.complete();
    await tester.pump();

    expect(state.selectedGroup?.uuid, 'g1');
    expect(state.selectedEntry?.uuid, 'e1');
  });

  testWidgets('compact vault navigation fits without layout overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final state = FakeVaultState(initialFilePath: '/tmp/vault.kdbx');
    await _unlockVault(tester, state);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('General'));
    await tester.pump();
    expect(find.text('Example'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Example'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Example'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _openVaultActions(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel('Vault actions').first);
  await tester.pump();
}

Future<void> _unlockVault(WidgetTester tester, FakeVaultState state) async {
  await tester.pumpWidget(appWith(state));

  await tester.tap(find.byType(MTextField));
  await tester.pump();
  await tester.enterText(find.byType(EditableText), 'correct');
  await tester.pump();
  await tester.tap(find.text('Unlock'));
  await tester.pump();
  await tester.pump();

  expect(state.isLocked, isFalse);
}

class _FakeFilePicker extends FilePicker {
  _FakeFilePicker({this.savePath});

  final String? savePath;

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
