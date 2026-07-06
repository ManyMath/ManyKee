import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_ui/keepass_ui.dart';
import 'package:manykee/src/state/native_vault_state.dart';

void main() {
  test('createDatabaseAtPath saves a fresh database and opens it', () async {
    final tempDir = await Directory.systemTemp.createTemp('manykee-created-db');
    final tempFile = File('${tempDir.path}/fresh.kdbx');

    final state = NativeVaultState();
    await state.createDatabaseAtPath(
      filePath: tempFile.path,
      password: 'fresh-pass',
      filename: 'fresh.kdbx',
    );

    expect(await tempFile.exists(), isTrue);
    expect(state.isLocked, isFalse);
    expect(state.lastFilePath, tempFile.path);
    expect(state.lastFilename, 'fresh.kdbx');
    expect(state.groups, isEmpty);
    expect(state.entries, isEmpty);
    expect(state.isDirty, isFalse);

    final entryUuid = await state.createEntry('');
    await state.updateEntry(entryUuid, <String, String?>{
      'Title': 'Created Database Entry',
      'UserName': 'manykee-created',
    });
    await state.saveDatabase(password: 'fresh-pass');

    await state.lock();
    state.dispose();

    final reopened = NativeVaultState();
    await reopened.unlockFromPath(
      filePath: tempFile.path,
      password: 'fresh-pass',
      filename: 'fresh.kdbx',
    );
    expect(
      reopened.entries.any((entry) => entry.title == 'Created Database Entry'),
      isTrue,
    );

    await reopened.lock();
    reopened.dispose();
    await tempDir.delete(recursive: true);
  });

  test('mutations mark dirty and save clears it after persisting to disk', () async {
    final sourcePath = _firstExisting(<String>[
      '../native/integration_test/fixtures/test_db_kdbx4_with_password_argon2id.kdbx',
      '../../apps/native/integration_test/fixtures/test_db_kdbx4_with_password_argon2id.kdbx',
      '../../rust/keepass-rs/tests/resources/test_db_kdbx4_with_password_argon2id.kdbx',
    ]);
    final tempDir = await Directory.systemTemp.createTemp(
      'manykee-native-state',
    );
    final tempFile = File('${tempDir.path}/state-test.kdbx');
    await File(sourcePath).copy(tempFile.path);

    final state = NativeVaultState();
    await state.unlockFromPath(
      filePath: tempFile.path,
      password: 'demopass',
      filename: 'state-test.kdbx',
    );

    final groupUuid = state.groups.isNotEmpty
        ? state.groups.first.uuid
        : await state.createGroup('', 'State Test Group');
    final entryUuid = await state.createEntry(groupUuid);
    await state.updateEntry(entryUuid, <String, String?>{
      'Title': 'ManyKee Dirty State',
      'UserName': 'manykee-state',
    });

    expect(state.isDirty, isTrue);

    await state.saveDatabase(password: 'demopass');
    expect(state.isDirty, isFalse);

    expect(() => state.saveDatabase(password: ''), throwsA(isA<StateError>()));

    await state.lock();
    state.dispose();

    final reopened = NativeVaultState();
    await reopened.unlockFromPath(
      filePath: tempFile.path,
      password: 'demopass',
      filename: 'state-test.kdbx',
    );

    final persisted = reopened.entries
        .where((entry) => entry.title == 'ManyKee Dirty State')
        .toList();
    expect(persisted, isNotEmpty);

    await reopened.lock();
    reopened.dispose();
    await tempDir.delete(recursive: true);
  });

  test('saveCopyAs writes an alternate file without clearing dirty state', () async {
    final sourcePath = _firstExisting(<String>[
      '../native/integration_test/fixtures/test_db_kdbx4_with_password_argon2id.kdbx',
      '../../apps/native/integration_test/fixtures/test_db_kdbx4_with_password_argon2id.kdbx',
      '../../rust/keepass-rs/tests/resources/test_db_kdbx4_with_password_argon2id.kdbx',
    ]);
    final tempDir = await Directory.systemTemp.createTemp(
      'manykee-native-copy-state',
    );
    final originalFile = File('${tempDir.path}/original.kdbx');
    final copyFile = File('${tempDir.path}/copy.kdbx');
    await File(sourcePath).copy(originalFile.path);

    final state = NativeVaultState();
    await state.unlockFromPath(
      filePath: originalFile.path,
      password: 'demopass',
      filename: 'original.kdbx',
    );

    final groupUuid = state.groups.isNotEmpty
        ? state.groups.first.uuid
        : await state.createGroup('', 'Copy Test Group');
    final entryUuid = await state.createEntry(groupUuid);
    await state.updateEntry(entryUuid, <String, String?>{
      'Title': 'ManyKee Copy State',
      'UserName': 'manykee-copy',
    });
    expect(state.isDirty, isTrue);

    await state.saveCopyAs(filePath: copyFile.path, password: 'demopass');

    expect(await copyFile.exists(), isTrue);
    expect(state.lastFilePath, originalFile.path);
    expect(state.lastFilename, 'original.kdbx');
    expect(state.isDirty, isTrue);

    await state.lock();
    state.dispose();

    final reopenedCopy = NativeVaultState();
    await reopenedCopy.unlockFromPath(
      filePath: copyFile.path,
      password: 'demopass',
      filename: 'copy.kdbx',
    );

    final copied = reopenedCopy.entries
        .where((entry) => entry.title == 'ManyKee Copy State')
        .toList();
    expect(copied, isNotEmpty);

    await reopenedCopy.lock();
    reopenedCopy.dispose();
    await tempDir.delete(recursive: true);
  });

  test('group create/rename/move/delete round trip', () async {
    final sourcePath = _firstExisting(<String>[
      '../native/integration_test/fixtures/test_db_kdbx4_with_password_argon2id.kdbx',
      '../../apps/native/integration_test/fixtures/test_db_kdbx4_with_password_argon2id.kdbx',
      '../../rust/keepass-rs/tests/resources/test_db_kdbx4_with_password_argon2id.kdbx',
    ]);
    final tempDir = await Directory.systemTemp.createTemp(
      'manykee-native-group-state',
    );
    final tempFile = File('${tempDir.path}/group-test.kdbx');
    await File(sourcePath).copy(tempFile.path);

    final state = NativeVaultState();
    await state.unlockFromPath(
      filePath: tempFile.path,
      password: 'demopass',
      filename: 'group-test.kdbx',
    );

    final topLevelUuid = await state.createGroup('', 'Top Level Group');
    final parentUuid = await state.createGroup(topLevelUuid, 'Parent Group');
    final siblingUuid = await state.createGroup(topLevelUuid, 'Sibling Group');
    final childUuid = await state.createGroup(parentUuid, 'Child Group');
    await state.renameGroup(childUuid, 'Renamed Child');

    final childNames = state.groups
        .expand(_flattenGroups)
        .map((g) => g.name)
        .toList();
    expect(childNames, contains('Renamed Child'));

    await state.moveGroup(childUuid, siblingUuid);
    await state.deleteGroup(childUuid);

    expect(state.isDirty, isTrue);

    await state.lock();
    state.dispose();
    await tempDir.delete(recursive: true);
  });
}

Iterable<VaultGroup> _flattenGroups(VaultGroup group) sync* {
  yield group;
  for (final child in group.children) {
    yield* _flattenGroups(child);
  }
}

String _firstExisting(List<String> candidates) {
  return candidates.firstWhere(
    (path) => File(path).existsSync(),
    orElse: () => throw StateError(
      'No test fixture found for candidates: ${candidates.join(', ')}',
    ),
  );
}
