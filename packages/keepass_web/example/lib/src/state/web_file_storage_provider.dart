import 'dart:convert';
import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:keepass_ui/keepass_ui.dart';
import 'package:web/web.dart' as web;

/// Compile-time-only switch for the E2E test harness's sessionStorage
/// mirror below. Must be enabled via `--dart-define=MANYKEE_E2E_SEMANTICS=true`
/// at build time (see scripts/build_extension.sh); a plain `kDebugMode`
/// gate isn't usable here because the E2E suite exercises a `--release`
/// build (matching what's shipped), so this is the only gate that
/// can never be toggled at runtime by an untrusted URL.
const bool _e2eSemanticsEnabled = bool.fromEnvironment('MANYKEE_E2E_SEMANTICS');

class WebFileStorageProvider implements StorageProvider {
  String? _currentName;
  DateTime? _lastModified;

  String? get currentName => _currentName;

  void rememberName(String? name) {
    _currentName = name;
  }

  @override
  Future<List<StorageItem>> list() async {
    final name = _currentName;
    if (name == null || name.isEmpty) {
      return const <StorageItem>[];
    }

    return <StorageItem>[
      StorageItem(
        name: name,
        lastModified: _lastModified,
      ),
    ];
  }

  @override
  Future<StorageOpenResult> open() async {
    final input = web.HTMLInputElement()
      ..type = 'file'
      ..accept = '.kdbx';
    final completer = Completer<StorageOpenResult>();

    input.addEventListener(
      'change',
      ((web.Event _) {
        final files = input.files;
        if (files == null || files.length == 0) {
          if (!completer.isCompleted) {
            completer.completeError(
              const StorageProviderUnavailableError('No file selected'),
            );
          }
          return;
        }

        final file = files.item(0);
        if (file == null) {
          if (!completer.isCompleted) {
            completer.completeError(
              const StorageProviderUnavailableError('No file selected'),
            );
          }
          return;
        }

        final reader = web.FileReader();
        reader.addEventListener(
          'load',
          ((web.Event _) {
            final buffer = reader.result as JSArrayBuffer;
            _currentName = file.name;
            _lastModified =
                DateTime.fromMillisecondsSinceEpoch(file.lastModified);
            if (!completer.isCompleted) {
              completer.complete(
                StorageOpenResult(
                  bytes: buffer.toDart.asUint8List(),
                  name: file.name,
                ),
              );
            }
          }).toJS,
        );
        reader.addEventListener(
          'error',
          ((web.Event _) {
            if (!completer.isCompleted) {
              completer.completeError(
                const StorageProviderUnavailableError(
                  'Failed to read the selected file',
                ),
              );
            }
          }).toJS,
        );
        reader.readAsArrayBuffer(file);
      }).toJS,
    );

    input.click();
    return completer.future;
  }

  @override
  Future<void> save(Uint8List bytes, {required String name}) async {
    final blob = web.Blob(
      <JSAny>[bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'application/octet-stream'),
    );
    final url = web.URL.createObjectURL(blob);
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = name
      ..style.display = 'none';

    web.document.body?.append(anchor);
    anchor.click();
    anchor.remove();

    _currentName = name;
    _lastModified = DateTime.now();

    // Expose the saved artifact for the standalone E2E harness without
    // depending on browser download behavior in headless mode. Gated behind
    // a compile-time define so a production build can't be made to mirror
    // the saved database into sessionStorage just by adding a URL query
    // param.
    if (_e2eSemanticsEnabled &&
        web.window.location.search.contains('e2e_semantics=1')) {
      web.window.sessionStorage.setItem(
        'manykee_last_download_name',
        name,
      );
      web.window.sessionStorage.setItem(
        'manykee_last_download_bytes',
        base64Encode(bytes),
      );
    }

    await Future<void>.delayed(const Duration(milliseconds: 100));
    web.URL.revokeObjectURL(url);
  }
}
