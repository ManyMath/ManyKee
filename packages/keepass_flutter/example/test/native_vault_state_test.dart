import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_flutter_example/src/state/native_vault_state.dart';

void main() {
  test('mutations mark dirty and save clears it after persisting to disk',
      () async {
    final stagedLibrary = await _stageNativeLibrary();
    final sourcePath = _firstExisting(<String>[
      // From example/ (where `flutter test` runs), then from keepass_flutter/.
      '../../../rust/keepass-rs/tests/resources/test_db_kdbx4_with_password_argon2id.kdbx',
      '../../../rust/keepass-rs/tests/resources/test_db_with_password.kdbx',
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
        .where((entry) => entry.title == 'Phase 34 Dirty State')
        .toList();
    expect(persisted, isNotEmpty);

    await reopened.lock();
    reopened.dispose();
    await tempDir.delete(recursive: true);
    if (stagedLibrary != null && await stagedLibrary.exists()) {
      await stagedLibrary.delete();
    }
  });
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
      'No test fixture found for candidates: ${candidates.join(', ')}',
    ),
  );
}
