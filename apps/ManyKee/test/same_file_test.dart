import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:manykee/src/merge/same_file.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('manykee_same_file_');
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  test('identical paths refer to the same file', () {
    final a = File('${tmp.path}/a.kdbx')..writeAsStringSync('a');
    expect(pathsReferToSameFile(a.path, a.path), isTrue);
  });

  test('different files in the same directory are distinct', () {
    final a = File('${tmp.path}/a.kdbx')..writeAsStringSync('a');
    expect(pathsReferToSameFile(a.path, '${tmp.path}/merged.kdbx'), isFalse);
  });

  test('a non-normalised path to the same file is detected', () {
    final a = File('${tmp.path}/a.kdbx')..writeAsStringSync('a');
    final sub = Directory('${tmp.path}/sub')..createSync();
    expect(pathsReferToSameFile('${sub.path}/../a.kdbx', a.path), isTrue);
  });

  test('a symlink to the file is detected', () {
    final a = File('${tmp.path}/a.kdbx')..writeAsStringSync('a');
    final link = Link('${tmp.path}/link.kdbx')..createSync(a.path);
    expect(pathsReferToSameFile(link.path, a.path), isTrue);
  });

  test('a not-yet-existing destination under a symlinked directory', () {
    final real = Directory('${tmp.path}/real')..createSync();
    final a = File('${real.path}/a.kdbx')..writeAsStringSync('a');
    final link = Link('${tmp.path}/alias')..createSync(real.path);
    expect(pathsReferToSameFile('${link.path}/a.kdbx', a.path), isTrue);
    expect(pathsReferToSameFile('${link.path}/new.kdbx', a.path), isFalse);
  });
}
