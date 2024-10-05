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
}
