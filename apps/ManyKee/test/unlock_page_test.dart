import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:manyui/manyui.dart';
import 'package:keepass_ui/keepass_ui.dart' show VaultEntry, VaultGroup;
import 'package:manykee/src/app.dart';
import 'package:manykee/src/state/manykee_vault_state.dart';
import 'package:manykee/src/state/unlock_error_mapper.dart';
import 'package:manykee/src/state/vault_state_provider.dart';

/// In-memory vault state: no native library, no file system.
///
/// Accepts [acceptedPassword]; any other password maps a wrong-password
/// error exactly like the native implementation does.
class FakeVaultState extends ManyKeeVaultState {
  @override
  Future<List<Map<String, dynamic>>> listYubiKeys() async =>
      const <Map<String, dynamic>>[];

  FakeVaultState({this.acceptedPassword = 'correct', String? initialFilePath})
      : _lastFilePath = initialFilePath;

  final String acceptedPassword;
  String? _lastFilePath;

  @override
  String? get lastFilePath => _lastFilePath;

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
    clearError();
    if (password != acceptedPassword) {
      final mapped = mapUnlockError('invalid credentials or corrupt database',
          filePath: filePath);
      setErrorWithDetail(mapped.code, mapped.message, detail: mapped.detail);
      return;
    }
    _lastFilePath = filePath;
    handleValue = 1;
    lastFilenameValue = filename ?? filePath;
    groupsValue = <VaultGroup>[
      VaultGroup(uuid: 'g1', name: 'General'),
    ];
    selectedGroupValue = groups.first;
    entriesValue = <VaultEntry>[
      VaultEntry(uuid: 'e1', title: 'Example', username: 'alice', url: ''),
    ];
    isLockedValue = false;
    notifyListeners();
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
    selectedGroupValue = group;
    notifyListeners();
  }

  @override
  Future<Map<String, dynamic>> readEntryFields(String entryUuid) async {
    return <String, dynamic>{
      'Title': 'Example',
      'UserName': 'alice',
      'URL': '',
      'Notes': '',
    };
  }

  @override
  Future<String?> readEntryField(String entryUuid, String fieldName) async {
    return fieldName == 'Password' ? 'hunter2' : null;
  }

  @override
  Future<Map<String, dynamic>?> getTotpCode(String entryUuid) async => null;
}

Widget appWith(FakeVaultState state) {
  return ProviderScope(
    overrides: <Override>[
      vaultStateProvider.overrideWith((ref) => state),
    ],
    child: const ManyKeeApp(),
  );
}

void main() {
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

  testWidgets('re-unlock view shows path and maps a wrong password error',
      (tester) async {
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
    // The raw error rides along as a muted detail line, not in the message.
    expect(find.text('invalid credentials or corrupt database'),
        findsOneWidget);
    expect(state.isLocked, isTrue);
  });

  testWidgets(
      'unlock page does NOT expose a merge-databases entry point '
      '(gated to an already-open vault, see vault_page_test.dart)',
      (tester) async {
    await tester.pumpWidget(appWith(FakeVaultState()));
    expect(find.text('Merge databases…'), findsNothing);
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
    expect(find.text('General'), findsOneWidget);

    // Default test surface is 800x600 — the narrow, stacked layout. Tapping
    // the group navigates to its entry list.
    await tester.tap(find.text('General'));
    await tester.pump();
    expect(find.text('Example'), findsOneWidget);
  });
}
