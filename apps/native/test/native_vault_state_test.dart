import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:manykee_native/src/state/native_vault_state.dart';

void main() {
  test('mutations mark dirty and save clears it after persisting to disk',
      () async {
    final sourcePath = _firstExisting(<String>[
      'apps/native/integration_test/fixtures/test_db_kdbx4_with_password_argon2id.kdbx',
      'rust/keepass-rs/tests/resources/test_db_kdbx4_with_password_argon2id.kdbx',
      '../../rust/keepass-rs/tests/resources/test_db_kdbx4_with_password_argon2id.kdbx',
    ]);
    final tempDir =
        await Directory.systemTemp.createTemp('manykee-native-state');
    final tempFile = File('${tempDir.path}/state-test.kdbx');
    await File(sourcePath).copy(tempFile.path);

    final state = NativeVaultState();
    await state.unlockNative(
      filePath: tempFile.path,
      password: 'demopass',
      filename: 'state-test.kdbx',
    );

    final groupUuid = state.groups.isNotEmpty
        ? state.groups.first.uuid
        : await state.createGroup('', 'State Test Group');
    final entryUuid = await state.createEntry(groupUuid);
    await state.updateEntry(entryUuid, <String, String?>{
      'Title': 'Phase 21 Dirty State',
      'UserName': 'native-state',
    });

    expect(state.isDirty, isTrue);

    await state.saveDatabase(password: 'demopass');
    expect(state.isDirty, isFalse);

    expect(
      () => state.saveDatabase(password: ''),
      throwsA(isA<StateError>()),
    );

    await state.lock();
    state.dispose();

    final reopened = NativeVaultState();
    await reopened.unlockNative(
      filePath: tempFile.path,
      password: 'demopass',
      filename: 'state-test.kdbx',
    );

    final persisted = reopened.entries
        .where((entry) => entry.title == 'Phase 21 Dirty State')
        .toList();
    expect(persisted, isNotEmpty);

    await reopened.lock();
    reopened.dispose();
    await tempDir.delete(recursive: true);
  });
}

String _firstExisting(List<String> candidates) {
  return candidates.firstWhere(
    (path) => File(path).existsSync(),
    orElse: () => throw StateError(
      'No test fixture found for candidates: ${candidates.join(', ')}',
    ),
  );
}
