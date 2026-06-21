import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_ui/keepass_ui.dart';

class _FakeVaultState extends VaultState {
  _FakeVaultState({
    required this.fields,
    this.readEntryFieldValues = const {},
  });

  final Map<String, dynamic> fields;
  final Map<String, String> readEntryFieldValues;
  final List<String> fetchedFields = [];

  @override
  Stream<int> get progress => const Stream.empty();

  @override
  Future<void> unlock({
    Uint8List? dbBytes,
    String? filePath,
    required String password,
    Uint8List? keyFileBytes,
    String? challengeResponseHex,
    String? filename,
  }) async {}

  @override
  Future<void> lock() async {}

  @override
  Future<void> selectGroup(VaultGroup group) async {}

  @override
  Future<Map<String, dynamic>> readEntryFields(String entryUuid) async {
    return fields;
  }

  @override
  Future<String?> readEntryField(String entryUuid, String fieldName) async {
    fetchedFields.add(fieldName);
    return readEntryFieldValues[fieldName];
  }

  @override
  Future<Map<String, dynamic>?> getTotpCode(String entryUuid) async => null;

  @override
  Future<String> createEntry(String groupUuid) async => '';

  @override
  Future<void> updateEntry(
    String entryUuid,
    Map<String, String?> fields, {
    Set<String> protectedFields = const <String>{},
  }) async {}

  @override
  Future<void> deleteEntry(String entryUuid) async {}

  @override
  Future<void> moveEntry(String entryUuid, String targetGroupUuid) async {}

  @override
  Future<String> createGroup(String parentGroupUuid, String name) async => '';

  @override
  Future<void> renameGroup(String groupUuid, String name) async {}

  @override
  Future<void> deleteGroup(String groupUuid) async {}

  @override
  Future<void> moveGroup(String groupUuid, String targetParentUuid) async {}

  @override
  Future<List<int>> saveDatabase({
    required String password,
    List<int>? keyFileBytes,
  }) async =>
      const [];
}

/// A [VaultState] whose `readEntryFields` completion order per entry UUID is
/// controlled by the test via [gateFor], so a race between an older and a
/// newer `_loadFields()` call can be reproduced deterministically.
class _RaceVaultState extends VaultState {
  _RaceVaultState(this.fieldsByUuid);

  final Map<String, Map<String, dynamic>> fieldsByUuid;
  final Map<String, Completer<void>> _gates = {};

  Completer<void> gateFor(String uuid) =>
      _gates.putIfAbsent(uuid, () => Completer<void>());

  @override
  Stream<int> get progress => const Stream.empty();

  @override
  Future<void> unlock({
    Uint8List? dbBytes,
    String? filePath,
    required String password,
    Uint8List? keyFileBytes,
    String? challengeResponseHex,
    String? filename,
  }) async {}

  @override
  Future<void> lock() async {}

  @override
  Future<void> selectGroup(VaultGroup group) async {}

  @override
  Future<Map<String, dynamic>> readEntryFields(String entryUuid) async {
    await gateFor(entryUuid).future;
    return fieldsByUuid[entryUuid]!;
  }

  @override
  Future<String?> readEntryField(String entryUuid, String fieldName) async =>
      null;

  @override
  Future<Map<String, dynamic>?> getTotpCode(String entryUuid) async => null;

  @override
  Future<String> createEntry(String groupUuid) async => '';

  @override
  Future<void> updateEntry(
    String entryUuid,
    Map<String, String?> fields, {
    Set<String> protectedFields = const <String>{},
  }) async {}

  @override
  Future<void> deleteEntry(String entryUuid) async {}

  @override
  Future<void> moveEntry(String entryUuid, String targetGroupUuid) async {}

  @override
  Future<String> createGroup(String parentGroupUuid, String name) async => '';

  @override
  Future<void> renameGroup(String groupUuid, String name) async {}

  @override
  Future<void> deleteGroup(String groupUuid) async {}

  @override
  Future<void> moveGroup(String groupUuid, String targetParentUuid) async {}

  @override
  Future<List<int>> saveDatabase({
    required String password,
    List<int>? keyFileBytes,
  }) async =>
      const [];
}

Future<void> _pumpEntryDetail(
  WidgetTester tester,
  VaultState vaultState,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: EntryDetail(
          entry: VaultEntry(
            uuid: 'entry-1',
            title: 'Example',
            username: 'user',
            url: '',
          ),
          vaultState: vaultState,
          clipboardManager: ClipboardManager(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the Password field even when its value was scrubbed',
      (tester) async {
    final vaultState = _FakeVaultState(
      fields: const {
        'Title': 'Example',
        'UserName': 'user',
        'Password': '',
        'URL': '',
        'Notes': '',
        'protected': {'Password': true},
      },
      readEntryFieldValues: const {'Password': 'hunter2'},
    );

    await _pumpEntryDetail(tester, vaultState);

    expect(find.text('Password'), findsOneWidget);
    expect(find.byTooltip('Show password'), findsOneWidget);
  });

  testWidgets(
      'fetches the real Password value on demand when reveal is pressed',
      (tester) async {
    final vaultState = _FakeVaultState(
      fields: const {
        'Title': 'Example',
        'UserName': 'user',
        'Password': '',
        'URL': '',
        'Notes': '',
        'protected': {'Password': true},
      },
      readEntryFieldValues: const {'Password': 'hunter2'},
    );

    await _pumpEntryDetail(tester, vaultState);

    expect(vaultState.fetchedFields, isEmpty);
    expect(find.text('hunter2'), findsNothing);

    await tester.tap(find.byTooltip('Show password'));
    await tester.pumpAndSettle();

    expect(vaultState.fetchedFields, ['Password']);
    expect(find.text('hunter2'), findsOneWidget);
  });

  testWidgets(
      'protected custom field is masked and fetched on demand, and the '
      "protected map itself isn't shown as a bogus custom field",
      (tester) async {
    final vaultState = _FakeVaultState(
      fields: const {
        'Title': 'Example',
        'UserName': 'user',
        'Password': 'plainpw',
        'URL': '',
        'Notes': '',
        'PIN': '',
        'protected': {'Password': false, 'PIN': true},
      },
      readEntryFieldValues: const {'PIN': '1234'},
    );

    await _pumpEntryDetail(tester, vaultState);

    expect(find.text('PIN'), findsOneWidget);
    expect(find.text('protected'), findsNothing);
    expect(find.text('1234'), findsNothing);

    // Two PasswordField instances exist here (Password + the protected PIN
    // custom field); the PIN one renders second.
    await tester.tap(find.byTooltip('Show password').at(1));
    await tester.pumpAndSettle();

    expect(vaultState.fetchedFields, ['PIN']);
    expect(find.text('1234'), findsOneWidget);
  });

  testWidgets('unprotected custom field renders as plain selectable text',
      (tester) async {
    final vaultState = _FakeVaultState(
      fields: const {
        'Title': 'Example',
        'UserName': 'user',
        'Password': 'plainpw',
        'URL': '',
        'Notes': '',
        'Note field': 'hello',
        'protected': {'Password': false},
      },
    );

    await _pumpEntryDetail(tester, vaultState);

    expect(find.text('hello'), findsOneWidget);
  });

  testWidgets(
      'a stale in-flight fetch from a previously-selected entry does not '
      'overwrite the currently-selected entry after switching quickly',
      (tester) async {
    final vaultState = _RaceVaultState({
      'entry-1': const {
        'Title': 'First',
        'UserName': 'user-one',
        'Password': 'pw-one',
        'URL': '',
        'Notes': '',
      },
      'entry-2': const {
        'Title': 'Second',
        'UserName': 'user-two',
        'Password': 'pw-two',
        'URL': '',
        'Notes': '',
      },
    });

    final entry1 = VaultEntry(
      uuid: 'entry-1',
      title: 'First',
      username: 'user-one',
      url: '',
    );
    final entry2 = VaultEntry(
      uuid: 'entry-2',
      title: 'Second',
      username: 'user-two',
      url: '',
    );

    Widget buildFor(VaultEntry entry) => MaterialApp(
          home: Scaffold(
            body: EntryDetail(
              entry: entry,
              vaultState: vaultState,
              clipboardManager: ClipboardManager(),
            ),
          ),
        );

    await tester.pumpWidget(buildFor(entry1));
    await tester.pump(); // entry-1's readEntryFields is now in flight

    await tester.pumpWidget(buildFor(entry2));
    await tester.pump(); // entry-2's readEntryFields is now in flight too

    // entry-2 (the currently-selected entry) resolves first.
    vaultState.gateFor('entry-2').complete();
    await tester.pumpAndSettle();

    expect(find.text('user-two'), findsOneWidget);

    // entry-1's stale fetch resolves after entry-2 is already showing; it
    // must not clobber the currently-displayed entry.
    vaultState.gateFor('entry-1').complete();
    await tester.pumpAndSettle();

    expect(find.text('user-two'), findsOneWidget);
    expect(find.text('user-one'), findsNothing);
  });
}
