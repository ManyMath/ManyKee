import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_flutter/keepass_flutter.dart';

void main() {
  test('mutations mark dirty and save clears it after persisting to disk',
      () async {
    final stagedLibrary = await _stageNativeLibrary();
    final sourcePath = _firstExisting(<String>[
      '../../rust/keepass-rs/tests/resources/test_db_kdbx4_with_password_argon2id.kdbx',
      '../../rust/keepass-rs/tests/resources/test_db_with_password.kdbx',
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
      'Title': 'Phase 34 Dirty State',
      'UserName': 'plugin-state',
    });

    expect(state.isDirty, isTrue);

    await state.saveDatabase(password: '');
    expect(state.isDirty, isFalse);

    await state.lock();
    state.dispose();

    final reopened = NativeVaultState();
    await reopened.unlockNative(
      filePath: tempFile.path,
      password: 'demopass',
      filename: 'state-test.kdbx',
    );

    final persisted = reopened.entries
        .where((entry) => entry.title == 'Phase 34 Dirty State')
        .toList();
    expect(persisted, isNotEmpty);

    await reopened.lock();
    reopened.dispose();
    await tempDir.delete(recursive: true);
    if (await stagedLibrary.exists()) {
      await stagedLibrary.delete();
    }
  });
}

Future<File> _stageNativeLibrary() async {
  final sourcePath = _firstExisting(<String>[
    '../keepass_cli/libkeepassxc_ffi.so',
    '../../packages/keepass_cli/libkeepassxc_ffi.so',
  ]);
  final staged = File('${Directory.current.path}/libkeepassxc_ffi.so');
  if (!await staged.exists()) {
    await File(sourcePath).copy(staged.path);
  }
  return staged;
}

String _firstExisting(List<String> candidates) {
  return candidates.firstWhere(
    (path) => File(path).existsSync(),
    orElse: () => throw StateError(
      'No test fixture found for candidates: ${candidates.join(', ')}',
    ),
  );
}
