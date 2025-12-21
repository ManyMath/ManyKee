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

  test('entry CRUD and saveDatabase round-trip through the worker isolate',
      () async {
    final api = KeePassNativeApi();
    final handle = await api.openFromPath(
      passwordFixturePath,
      password: 'demopass',
    );

    try {
      final sourceGroupUuid = await _firstWritableGroupUuid(api, handle);
      final targetGroupUuid = await api.createGroup(
        handle,
        sourceGroupUuid,
        'Phase 21 Target',
      );

      final entryUuid = await api.createEntry(handle, sourceGroupUuid);
      await api.setEntryField(handle, entryUuid, 'Title', 'Phase 21 Entry');
      await api.setEntryField(
        handle,
        entryUuid,
        'Password',
        'super-secret',
        isProtected: true,
      );

      final fields = await api.readEntryFields(handle, entryUuid);
      expect(fields['Title'], 'Phase 21 Entry');
      expect(fields['Password'], 'super-secret');

      await api.moveEntry(handle, entryUuid, targetGroupUuid);
      final movedEntries = await api.listEntries(handle, targetGroupUuid);
      expect(
        movedEntries.any((entry) => entry['uuid'] == entryUuid),
        isTrue,
      );

      final savedBytes = await api.saveDatabase(handle, password: 'demopass');
      final savedFile = await _writeTempDatabase(savedBytes, suffix: '.kdbx');
      final reopenedHandle = await api.openFromPath(
        savedFile.path,
        password: 'demopass',
      );
      try {
        final reopenedEntries =
            await api.listEntries(reopenedHandle, targetGroupUuid);
        expect(
          reopenedEntries.any((entry) => entry['uuid'] == entryUuid),
          isTrue,
        );
        final reopenedFields = await api.readEntryFields(
          reopenedHandle,
          entryUuid,
        );
        expect(reopenedFields['Title'], 'Phase 21 Entry');
        expect(reopenedFields['Password'], 'super-secret');
      } finally {
        await api.closeDatabase(reopenedHandle);
        await savedFile.delete();
      }
    } finally {
      await api.closeDatabase(handle);
      await api.dispose();
    }
  });

  test('group CRUD operations run through the worker isolate', () async {
    final api = KeePassNativeApi();
    final handle = await api.openFromPath(
      passwordFixturePath,
      password: 'demopass',
    );

    try {
      final parentUuid = await _firstWritableGroupUuid(api, handle);
      final targetUuid =
          await api.createGroup(handle, parentUuid, 'Move Target');
      final groupUuid =
          await api.createGroup(handle, parentUuid, 'Phase 21 Group');

      await api.renameGroup(handle, groupUuid, 'Phase 21 Renamed');
      var groups = await api.listGroups(handle, parentUuid);
      expect(
          groups.any((group) => group['name'] == 'Phase 21 Renamed'), isTrue);

      await api.moveGroup(handle, groupUuid, targetUuid);
      groups = await api.listGroups(handle, targetUuid);
      expect(groups.any((group) => group['uuid'] == groupUuid), isTrue);

      await api.deleteGroup(handle, groupUuid);
      groups = await api.listGroups(handle, targetUuid);
      expect(groups.any((group) => group['uuid'] == groupUuid), isFalse);
    } finally {
      await api.closeDatabase(handle);
      await api.dispose();
    }
  });

  test(
      'saveDatabase preserves composite key databases when keyFileBytes are provided',
      () async {
    final api = KeePassNativeApi();
    final keyFileBytes = await File(keyFilePath).readAsBytes();
    final handle = await api.openFromPathWithKeyFile(
      keyFileFixturePath,
      password: 'demopass',
      keyFilePath: keyFilePath,
    );

    try {
      final sourceGroupUuid = await _firstWritableGroupUuid(api, handle);
      final entryUuid = await api.createEntry(handle, sourceGroupUuid);
      await api.setEntryField(handle, entryUuid, 'Title', 'Composite Save');

      final savedBytes = await api.saveDatabase(
        handle,
        password: 'demopass',
        keyFileBytes: keyFileBytes,
      );
      final savedFile = await _writeTempDatabase(savedBytes, suffix: '.kdbx');
      final reopenedHandle = await api.openFromPathWithKeyFile(
        savedFile.path,
        password: 'demopass',
        keyFilePath: keyFilePath,
      );
      try {
        final entries = await api.listEntries(reopenedHandle, sourceGroupUuid);
        expect(entries.any((entry) => entry['uuid'] == entryUuid), isTrue);
      } finally {
        await api.closeDatabase(reopenedHandle);
        await savedFile.delete();
      }
    } finally {
      await api.closeDatabase(handle);
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

Future<String> _firstWritableGroupUuid(KeePassNativeApi api, int handle) async {
  final groups = await api.listGroups(handle, '');
  if (groups.isEmpty) {
    return '';
  }
  return groups.first['uuid']! as String;
}

Future<File> _writeTempDatabase(List<int> bytes,
    {required String suffix}) async {
  final file = File(
    '${Directory.systemTemp.path}/manykee_test_${DateTime.now().microsecondsSinceEpoch}$suffix',
  );
  await file.writeAsBytes(bytes, flush: true);
  return file;
}
