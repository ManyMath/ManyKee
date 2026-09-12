import 'dart:io';
import 'package:test/test.dart';
import 'package:keepass/keepass.dart';

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
    bool leftoverTempDir() => Directory.systemTemp
        .listSync()
        .whereType<Directory>()
        .any((e) => e.uri.pathSegments.reversed
            .firstWhere((s) => s.isNotEmpty, orElse: () => '')
            .startsWith('manykee_save_'));
    try {
      final bytes = db.saveBytes(password: 'demopass');
      expect(bytes, isNotEmpty);
      expect(leftoverTempDir(), isFalse,
          reason: 'saveBytes must delete its temp directory afterward');

      final reopenPath =
          '${Directory.systemTemp.path}/manykee_test_reopen.kdbx';
      File(reopenPath).writeAsBytesSync(bytes);
      try {
        final reopened = Database.open(reopenPath, password: 'demopass');
        try {
          expect(reopened.rootGroup.uuid, isNotEmpty);
        } finally {
          reopened.close();
        }
      } finally {
        final f = File(reopenPath);
        if (f.existsSync()) {
          f.deleteSync();
        }
      }
    } finally {
      db.close();
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
      final reopenPath =
          '${Directory.systemTemp.path}/manykee_test_created.kdbx';
      File(reopenPath).writeAsBytesSync(bytes);
      try {
        final reopened = Database.open(reopenPath, password: 'a-new-password');
        try {
          expect(reopened.rootGroup.uuid, root.uuid);
        } finally {
          reopened.close();
        }
      } finally {
        final f = File(reopenPath);
        if (f.existsSync()) {
          f.deleteSync();
        }
      }
    } finally {
      db.close();
    }
  });
}
