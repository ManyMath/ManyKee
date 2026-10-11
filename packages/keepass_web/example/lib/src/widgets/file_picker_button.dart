import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// A button that triggers the browser's native file picker.
class FilePickerButton extends StatelessWidget {
  final String label;
  final String accept;
  final void Function(String filename, Uint8List bytes)? onFilePicked;
  final String? selectedFilename;
  final bool enabled;

  const FilePickerButton({
    super.key,
    required this.label,
    required this.accept,
    this.onFilePicked,
    this.selectedFilename,
    this.enabled = true,
  });

  static Future<(String, Uint8List)?> pickFile(String accept) async {
    final input = web.HTMLInputElement()
      ..type = 'file'
      ..accept = accept;
    input.click();

    final completer = Completer<(String, Uint8List)?>();

    input.addEventListener(
      'change',
      ((web.Event event) {
        final files = input.files;
        if (files == null || files.length == 0) {
          completer.complete(null);
          return;
        }
        final file = files.item(0)!;
        final reader = web.FileReader();
        reader.readAsArrayBuffer(file);
        reader.addEventListener(
          'load',
          ((web.Event _) {
            final buffer = reader.result as JSArrayBuffer;
            final bytes = buffer.toDart.asUint8List();
            completer.complete((file.name, bytes));
          }).toJS,
        );
        reader.addEventListener(
          'error',
          ((web.Event _) {
            completer.complete(null);
          }).toJS,
        );
      }).toJS,
    );

    return completer.future;
  }

  String _truncatedFilename(String name) {
    if (name.length <= 30) return name;
    return '${name.substring(0, 27)}...';
  }

  @override
  Widget build(BuildContext context) {
    final displayText = selectedFilename != null
        ? _truncatedFilename(selectedFilename!)
        : label;

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: enabled ? () => _pickAndNotify() : null,
        icon: Icon(
          selectedFilename != null ? Icons.description : Icons.folder_open,
        ),
        label: Text(
          displayText,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Future<void> _pickAndNotify() async {
    final result = await pickFile(accept);
    if (result != null) {
      onFilePicked?.call(result.$1, result.$2);
    }
  }
}
