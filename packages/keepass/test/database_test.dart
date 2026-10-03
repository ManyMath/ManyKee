import 'dart:io';
import 'package:test/test.dart';
import 'package:keepass/keepass.dart';
import 'package:keepass/src/error.dart' show readLastNativeErrorMessage;

void main() {
  // Fixture database path -- KDBX4 with password "demopass" (Argon2id)
  late String fixturePath;

  setUpAll(() {
    final candidates = [
      'test/fixtures/test.kdbx',
      '../../rust/keepass-rs/tests/resources/test_db_kdbx4_with_password_argon2id.kdbx',
    ];
    fixturePath = candidates.firstWhere(
      (p) => File(p).existsSync(),
      orElse: () => throw StateError(
        'No test fixture found. '
        'Run: cargo build -p keepassxc-ffi first and ensure fixture DBs exist.',
      ),
    );
  });

  test('open database and read root group', () {
    final db = Database.open(fixturePath, password: 'demopass');
    try {
      final root = db.rootGroup;
      expect(root.uuid, isNotEmpty);
    } finally {
      db.close();
    }
  });

  test('Database.close prevents double-free', () {
    final db = Database.open(fixturePath, password: 'demopass');
    db.close();
    expect(() => db.rootGroup, throwsStateError);
    // Second close is a no-op, should not crash
    db.close();
  });

  test('Entry.toString degrades gracefully after Database.close', () {
    final db = Database.open(fixturePath, password: 'demopass');
    final entry = Entry(db, 'not-a-real-uuid');
    db.close();
    expect(entry.toString(), equals('Entry(not-a-real-uuid)'));
  });

  test('saveBytes returns a re-openable database and cleans up its temp dir',
      () {
    final db = Database.open(fixturePath, password: 'demopass');
    // Other suites (or other checkouts) may be saving at the same time, so
    // only directories that appeared during this call count as leftovers.
    Set<String> saveTempDirs() => Directory.systemTemp
        .listSync()
        .whereType<Directory>()
        .map((e) => e.path)
        .where((path) =>
            path.split(Platform.pathSeparator).last.startsWith('manykee_save_'))
        .toSet();
    try {
      final before = saveTempDirs();
      final bytes = db.saveBytes(password: 'demopass');
      expect(bytes, isNotEmpty);
      final leftovers = saveTempDirs().difference(before);
      // A concurrent save elsewhere may still be running; ignore anything
      // that disappears on its own within a moment.
      if (leftovers.isNotEmpty) {
        sleep(const Duration(milliseconds: 200));
      }
      expect(leftovers.where((path) => Directory(path).existsSync()), isEmpty,
          reason: 'saveBytes must delete its temp directory afterward');

      final reopenDir =
          Directory.systemTemp.createTempSync('manykee_test_reopen_');
      try {
        final reopenPath = '${reopenDir.path}/reopen.kdbx';
        File(reopenPath).writeAsBytesSync(bytes);
        final reopened = Database.open(reopenPath, password: 'demopass');
        try {
          expect(reopened.rootGroup.uuid, isNotEmpty);
        } finally {
          reopened.close();
        }
      } finally {
        reopenDir.deleteSync(recursive: true);
      }
    } finally {
      db.close();
    }
  });

  test('KeePassError carries the native status code, not a blanket -1', () {
    const missingUuid = '00000000-0000-0000-0000-00000000beef';
    final db = Database.open(fixturePath, password: 'demopass');
    try {
      // Status-returning call (checkResult path).
      expect(
        () => Group(db, missingUuid).name = 'renamed',
        throwsA(isA<KeePassError>()
            .having((e) => e.code, 'code', KeePassError.notFound)
            .having((e) => e.message, 'message',
                startsWith('Failed to set group name: Group not found'))),
      );
      // Count call that returns a negative status instead of a count.
      expect(
        () => Group(db, missingUuid).entryCount,
        throwsA(isA<KeePassError>()
            .having((e) => e.code, 'code', KeePassError.notFound)),
      );
      expect(
        () => Group(db, missingUuid).groupCount,
        throwsA(isA<KeePassError>()
            .having((e) => e.code, 'code', KeePassError.notFound)),
      );
      // Null-pointer calls have no status to report.
      expect(
        () => Group(db, missingUuid).name,
        throwsA(isA<KeePassError>()
            .having((e) => e.code, 'code', KeePassError.unknownCode)),
      );
    } finally {
      db.close();
    }
  });

  test('listYubiKeys never reports a failed enumeration as "no keys"', () {
    // Enumeration can only be forced to fail natively, so this pins the
    // contract on whatever hardware is present: a returned list (empty or
    // not) means no native error is pending; a failure must throw.
    try {
      final keys = Database.listYubiKeys();
      expect(keys, isA<List<Map<String, dynamic>>>());
      expect(readLastNativeErrorMessage(), isNull,
          reason: 'listYubiKeys returned $keys with a native error pending');
    } on KeePassError catch (error) {
      expect(error.message, startsWith('Failed to enumerate YubiKeys'));
    }
  });

  test('Database.create returns a fresh, empty, saveable database', () {
    final db = Database.create();
    try {
      final root = db.rootGroup;
      expect(root.uuid, isNotEmpty);
      expect(root.groups, isEmpty);
      expect(root.entries, isEmpty);

      final bytes = db.saveBytes(password: 'a-new-password');
      final reopenDir =
          Directory.systemTemp.createTempSync('manykee_test_created_');
      try {
        final reopenPath = '${reopenDir.path}/created.kdbx';
        File(reopenPath).writeAsBytesSync(bytes);
        final reopened = Database.open(reopenPath, password: 'a-new-password');
        try {
          expect(reopened.rootGroup.uuid, root.uuid);
        } finally {
          reopened.close();
        }
      } finally {
        reopenDir.deleteSync(recursive: true);
      }
    } finally {
      db.close();
    }
  });

  test('Database.create supports soft delete into the recycle bin', () {
    final db = Database.create();
    try {
      final entry = db.rootGroup.createEntry();
      entry.setField('Title', 'Disposable');

      entry.delete();

      expect(
        db.rootGroup.entries.map((e) => e.uuid),
        isNot(contains(entry.uuid)),
      );
      final recycled = db.rootGroup.groups
          .expand((group) => group.entries)
          .map((e) => e.uuid);
      expect(recycled, contains(entry.uuid));
    } finally {
      db.close();
    }
  });

  test('KeePassError exposes the recycle-bin status code', () {
    expect(KeePassError.recycleBinDisabled, -11);
  });
}
