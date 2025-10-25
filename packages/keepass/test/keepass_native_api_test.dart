import 'dart:io';

import 'package:keepass/keepass.dart';
import 'package:test/test.dart';

void main() {
  late String passwordFixturePath;
  late String keyFileFixturePath;
  late String keyFilePath;

  setUpAll(() {
    passwordFixturePath = _firstExisting(<String>[
      'test/fixtures/test.kdbx',
      'rust/keepass-rs/tests/resources/test_db_kdbx4_with_password_argon2id.kdbx',
      '../../rust/keepass-rs/tests/resources/test_db_kdbx4_with_password_argon2id.kdbx',
    ]);
    keyFileFixturePath = _firstExisting(<String>[
      'rust/keepass-rs/tests/resources/test_db_kdbx4_with_keyfile_v2.kdbx',
      '../../rust/keepass-rs/tests/resources/test_db_kdbx4_with_keyfile_v2.kdbx',
    ]);
    keyFilePath = _firstExisting(<String>[
      'rust/keepass-rs/tests/resources/test_db_kdbx4_with_keyfile_v2.keyx',
      '../../rust/keepass-rs/tests/resources/test_db_kdbx4_with_keyfile_v2.keyx',
    ]);
  });

  test('openFromPath unlocks Argon2 database from the worker isolate',
      () async {
    final api = KeePassNativeApi();
    final handle = await api.openFromPath(
      passwordFixturePath,
      password: 'demopass',
    );

    try {
      expect(handle, greaterThan(0));
      await _expectDatabaseHasContent(api, handle);
    } finally {
      await api.closeDatabase(handle);
      await api.dispose();
    }
  });

  test('openFromPathWithKeyFile still works after isolate offload', () async {
    final api = KeePassNativeApi();
    final handle = await api.openFromPathWithKeyFile(
      keyFileFixturePath,
      password: 'demopass',
      keyFilePath: keyFilePath,
    );

    try {
      final entries = await _listFirstAvailableEntries(api, handle);
      expect(entries, isNotEmpty);

      final fields = await api.readEntryFields(
        handle,
        entries.first['uuid']! as String,
      );
      expect(handle, greaterThan(0));
      expect(fields['Title'], isNotNull);
    } finally {
      await api.closeDatabase(handle);
      await api.dispose();
    }
  });

  test('closeDatabase then reopenFromPath supports native re-unlock flows',
      () async {
    final api = KeePassNativeApi();
    final firstHandle = await api.openFromPath(
      passwordFixturePath,
      password: 'demopass',
    );
    await api.closeDatabase(firstHandle);

    final secondHandle = await api.openFromPath(
      passwordFixturePath,
      password: 'demopass',
    );

    try {
      expect(secondHandle, isNot(firstHandle));
      await _expectDatabaseHasContent(api, secondHandle);
    } finally {
      await api.closeDatabase(secondHandle);
      await api.dispose();
    }
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

Future<void> _expectDatabaseHasContent(KeePassNativeApi api, int handle) async {
  final groups = await api.listGroups(handle, '');
  if (groups.isNotEmpty) {
    return;
  }

  final entries = await api.listEntries(handle, '');
  expect(entries, isNotEmpty);
}

Future<List<Map<String, dynamic>>> _listFirstAvailableEntries(
  KeePassNativeApi api,
  int handle,
) async {
  final rootEntries = await api.listEntries(handle, '');
  if (rootEntries.isNotEmpty) {
    return rootEntries;
  }

  final groups = await api.listGroups(handle, '');
  expect(groups, isNotEmpty);
  return api.listEntries(handle, groups.first['uuid']! as String);
}
