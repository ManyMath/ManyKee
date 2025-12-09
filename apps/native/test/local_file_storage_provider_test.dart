import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manykee_native/src/state/local_file_storage_provider.dart';

class _FakeFilePicker extends FilePicker {
  _FakeFilePicker(this.path, this.name);

  final String path;
  final String name;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    return FilePickerResult(<PlatformFile>[
      PlatformFile(name: name, path: path, size: await File(path).length()),
    ]);
  }
}

void main() {
  test('open reads bytes and save writes back to the remembered path',
      () async {
    final tempDir = await Directory.systemTemp.createTemp('manykee-storage');
    final file = File('${tempDir.path}/vault.kdbx');
    await file.writeAsBytes(const <int>[1, 2, 3], flush: true);

    FilePicker.platform = _FakeFilePicker(file.path, 'vault.kdbx');
    final provider = LocalFileStorageProvider();

    final opened = await provider.open();
    expect(opened.name, 'vault.kdbx');
    expect(opened.bytes, const <int>[1, 2, 3]);

    await provider.save(Uint8List.fromList(const <int>[9, 8, 7]),
        name: opened.name);
    expect(await file.readAsBytes(), const <int>[9, 8, 7]);

    final listed = await provider.list();
    expect(listed.single.path, file.path);
    expect(listed.single.name, 'vault.kdbx');

    await tempDir.delete(recursive: true);
  });
}
