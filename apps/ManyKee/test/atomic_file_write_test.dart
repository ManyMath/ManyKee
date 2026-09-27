import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:manykee/src/state/atomic_file_write.dart';
import 'package:manykee/src/state/local_file_storage_provider.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('manykee-atomic-write');
  });

  tearDown(() async {
    if (!Platform.isWindows) {
      await Process.run('chmod', <String>['-R', 'u+rwx', tmp.path]);
    }
    await tmp.delete(recursive: true);
  });

  List<String> leftovers() => tmp
      .listSync()
      .map((e) => e.uri.pathSegments.where((s) => s.isNotEmpty).last)
      .where((name) => name.endsWith('.tmp'))
      .toList();

  test('replaces the contents of an existing file', () async {
    final file = File('${tmp.path}/vault.kdbx')
      ..writeAsBytesSync(const <int>[1, 2, 3]);

    await writeFileAtomically(file.path, const <int>[9, 8, 7, 6]);

    expect(file.readAsBytesSync(), const <int>[9, 8, 7, 6]);
    expect(leftovers(), isEmpty);
  });

  test('creates the file when it does not exist yet', () async {
    final file = File('${tmp.path}/new.kdbx');

    await writeFileAtomically(file.path, const <int>[4, 2]);

    expect(file.readAsBytesSync(), const <int>[4, 2]);
    expect(leftovers(), isEmpty);
  });

  test('leaves the destination intact when the write fails', () async {
    final file = File('${tmp.path}/vault.kdbx')
      ..writeAsBytesSync(const <int>[1, 2, 3]);

    // Simulate a crash/disk-full part-way through writing the new bytes.
    Future<void> failingWriter(File f, List<int> bytes) async {
      await f.writeAsBytes(bytes.sublist(0, 1), flush: true);
      throw const FileSystemException('No space left on device');
    }

    await expectLater(
      writeFileAtomically(file.path, const <int>[
        9,
        8,
        7,
        6,
      ], writeBytes: failingWriter),
      throwsA(isA<FileSystemException>()),
    );

    expect(file.readAsBytesSync(), const <int>[1, 2, 3]);
    expect(leftovers(), isEmpty);
  });

  test('keeps the original permission bits', () async {
    final file = File('${tmp.path}/vault.kdbx')
      ..writeAsBytesSync(const <int>[1]);
    await Process.run('chmod', <String>['600', file.path]);

    await writeFileAtomically(file.path, const <int>[2]);

    expect(file.statSync().mode & 0x1ff, 0x180); // 0600
    expect(file.readAsBytesSync(), const <int>[2]);
  }, skip: Platform.isWindows ? 'POSIX permissions only' : false);

  test('writes through a symlink without replacing the link', () async {
    final real = File('${tmp.path}/real.kdbx')
      ..writeAsBytesSync(const <int>[1]);
    final link = Link('${tmp.path}/link.kdbx')..createSync(real.path);

    await writeFileAtomically(link.path, const <int>[5, 5]);

    expect(FileSystemEntity.isLinkSync(link.path), isTrue);
    expect(real.readAsBytesSync(), const <int>[5, 5]);
  }, skip: Platform.isWindows ? 'symlinks need elevation on Windows' : false);

  test(
    'falls back to an in-place write when no sibling file can be created',
    () async {
      final file = File('${tmp.path}/vault.kdbx')
        ..writeAsBytesSync(const <int>[1, 2, 3]);
      await Process.run('chmod', <String>['555', tmp.path]);
      try {
        File('${tmp.path}/probe').createSync();
        markTestSkipped('running with permissions that ignore chmod');
        return;
      } on FileSystemException {
        // Expected: the directory is not writable.
      }

      await writeFileAtomically(file.path, const <int>[7]);

      expect(file.readAsBytesSync(), const <int>[7]);
    },
    skip: Platform.isWindows ? 'POSIX permissions only' : false,
  );

  test('LocalFileStorageProvider.save replaces the vault atomically', () async {
    final file = File('${tmp.path}/vault.kdbx')
      ..writeAsBytesSync(const <int>[1, 2, 3]);
    final provider = LocalFileStorageProvider(initialPath: file.path);

    await provider.save(
      Uint8List.fromList(const <int>[9, 9]),
      name: 'vault.kdbx',
    );

    expect(file.readAsBytesSync(), const <int>[9, 9]);
    expect(leftovers(), isEmpty);
  });
}
