import 'dart:io';

import 'package:keepass/keepass.dart';
import 'package:test/test.dart';

import 'support/native_library_names.dart';

// Canonical fixture password provenance: `FIXTURE_PASSWORD` in
// `rust/keepassxc/tests/bidirectional_parity.rs`.
const String _fixturePassword = 'manykee-fixture-password';

const String _fixtureSubdir = 'fixtures/compat/official/keepassxc/2.7.12';
const String _requireEnvVar = 'MANYKEE_REQUIRE_OFFICIAL_TOOLS';

void main() {
  late _NativeLibrarySetup nativeLibrary;

  setUpAll(() async {
    nativeLibrary = await _prepareNativeLibrary();
  });

  tearDownAll(() async {
    final staged = nativeLibrary.staged;
    if (staged != null && await staged.exists()) {
      await staged.delete();
    }
  });

  test('keepassxc-password-basic.kdbx unlocks via Database.open', () async {
    await _runSmoke(
      fixtureName: 'keepassxc-password-basic.kdbx',
      nativeLibrary: nativeLibrary,
    );
  });

  test('keepassxc-richcontent.kdbx unlocks via Database.open', () async {
    await _runSmoke(
      fixtureName: 'keepassxc-richcontent.kdbx',
      nativeLibrary: nativeLibrary,
    );
  });
}

Future<void> _runSmoke({
  required String fixtureName,
  required _NativeLibrarySetup nativeLibrary,
}) async {
  final required = Platform.environment[_requireEnvVar] == '1';

  if (!nativeLibrary.available) {
    final reason =
        'skipped: ${_nativeLibraryFileNames.join(' or ')} not built: run '
        '`cargo build --manifest-path rust/Cargo.toml -p keepassxc-ffi`';
    if (required) {
      fail('$_requireEnvVar=1 but $reason');
    }
    markTestSkipped(reason);
    return;
  }

  final fixturePath = _findOfficialFixture(fixtureName);
  if (fixturePath == null) {
    final reason = 'skipped: fixture $fixtureName not found under '
        '$_fixtureSubdir/ (searched upward from ${Directory.current.path})';
    if (required) {
      fail('$_requireEnvVar=1 but $reason');
    }
    markTestSkipped(reason);
    return;
  }

  final tempDir = await Directory.systemTemp.createTemp('manykee-official-');
  try {
    final tempFile = File('${tempDir.path}/$fixtureName');
    await File(fixturePath).copy(tempFile.path);

    final db = Database.open(tempFile.path, password: _fixturePassword);
    try {
      final root = db.rootGroup;
      expect(root.uuid, isNotEmpty,
          reason: 'root group should be present for $fixtureName');
      final hasContent = root.groups.isNotEmpty || root.entries.isNotEmpty;
      expect(hasContent, isTrue,
          reason: 'root group should contain groups or entries '
              'for $fixtureName at $fixturePath');
    } finally {
      db.close();
    }
  } finally {
    await tempDir.delete(recursive: true);
  }
}

/// Climbs from the current working directory up to 6 levels looking for
/// `fixtures/compat/official/keepassxc/2.7.12/<name>`. Returns the absolute
/// path on success, or null if not found.
String? _findOfficialFixture(String name) {
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    final candidate = File('${dir.path}/$_fixtureSubdir/$name');
    if (candidate.existsSync()) {
      return candidate.absolute.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      break;
    }
    dir = parent;
  }
  return null;
}

final List<String> _nativeLibraryFileNames =
    nativeLibraryFileNames(Platform.operatingSystem);

/// Output locations also probed by the production loader.
final List<String> _cargoOutputDirectories = [
  '../../rust/target/debug',
  '../../rust/target/release',
  'rust/target/debug',
  'rust/target/release',
];

/// A staged copy is owned by this test and removed afterwards.
typedef _NativeLibrarySetup = ({bool available, File? staged});

Future<_NativeLibrarySetup> _prepareNativeLibrary() async {
  for (final name in _nativeLibraryFileNames) {
    for (final directory in _cargoOutputDirectories) {
      if (await File('$directory/$name').exists()) {
        return (available: true, staged: null);
      }
    }
    if (await File('${Directory.current.path}/$name').exists()) {
      return (available: true, staged: null);
    }
  }

  for (final name in _nativeLibraryFileNames) {
    for (final directory in ['../keepass_cli', '../../packages/keepass_cli']) {
      final source = File('$directory/$name');
      if (await source.exists()) {
        final staged = File('${Directory.current.path}/$name');
        await _copyAtomically(source, staged);
        return (available: true, staged: staged);
      }
    }
  }
  return (available: false, staged: null);
}

/// Copies [source] to a uniquely named temporary file beside [destination]
/// and renames it into place, so a concurrent test run that loads
/// [destination] never sees a half-written library (`dlopen` accepts one and
/// the process then dies with SIGBUS).
Future<void> _copyAtomically(File source, File destination) async {
  final temp = File(
    '${destination.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp',
  );
  try {
    await source.copy(temp.path);
    await temp.rename(destination.path);
  } catch (_) {
    if (await temp.exists()) {
      await temp.delete();
    }
    rethrow;
  }
}
