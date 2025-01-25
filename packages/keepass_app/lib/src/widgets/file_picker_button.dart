import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// A button that triggers the browser's native file picker via [web.HTMLInputElement].
///
/// Uses `package:web` (NOT `dart:html`) to create an invisible `<input type="file">`
/// element, click it programmatically, and read the selected file's bytes via
/// [web.FileReader.readAsArrayBuffer].
class FilePickerButton extends StatelessWidget {
  /// Button text when no file is selected.
  final String label;

  /// File type filter for the browser picker (e.g. `.kdbx`, `.key,.keyx,.xml`).
  final String accept;

  /// Callback invoked with the selected file's name and raw bytes.
  final void Function(String filename, Uint8List bytes)? onFilePicked;

  /// When set, shows the filename on the button (truncated to 30 chars).
  final String? selectedFilename;

  /// Whether the button is interactive.
  final bool enabled;

  const FilePickerButton({
    super.key,
    required this.label,
    required this.accept,
    this.onFilePicked,
    this.selectedFilename,
    this.enabled = true,
  });

  /// Pick a file with the given [accept] filter.
  ///
  /// Returns a `(filename, bytes)` pair, or `null` if the user cancelled.
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
