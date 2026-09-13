import 'dart:io';

import 'package:keepass/keepass.dart';
import 'package:test/test.dart';

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
    const reason = 'skipped: libkeepassxc_ffi.so not built: run '
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

const String _nativeLibraryFileName = 'libkeepassxc_ffi.so';

/// Where `cargo build -p keepassxc-ffi` drops its output, relative to this
/// package directory (`dart test`'s CWD) and to the monorepo root.
/// `native_library.dart` probes these same locations itself, so when one of
/// them exists the library needs no staging at all.
const List<String> _cargoOutputCandidates = <String>[
  '../../rust/target/debug/$_nativeLibraryFileName',
  '../../rust/target/release/$_nativeLibraryFileName',
  'rust/target/debug/$_nativeLibraryFileName',
  'rust/target/release/$_nativeLibraryFileName',
];

/// Last-resort sources: a copy another package's test run staged into its
/// own directory. Only consulted when no cargo output exists.
const List<String> _siblingStagedCandidates = <String>[
  '../keepass_cli/$_nativeLibraryFileName',
  '../../packages/keepass_cli/$_nativeLibraryFileName',
];

/// `available` is whether `native_library.dart` can load `libkeepassxc_ffi.so`
/// from this test's CWD. `staged` is the copy this test run placed in the
/// CWD and must delete afterwards, or null when nothing was copied (the
/// loader finds the cargo output directly, a copy was already present, or
/// no source exists).
typedef _NativeLibrarySetup = ({bool available, File? staged});

/// Makes `libkeepassxc_ffi.so` loadable by `native_library.dart`, copying it
/// next to the Dart test runner's CWD only when the loader would not find
/// the cargo output on its own. Mirrors the helper in
/// `packages/keepass_cli/test/official_fixture_smoke_test.dart`.
Future<_NativeLibrarySetup> _prepareNativeLibrary() async {
  for (final candidate in _cargoOutputCandidates) {
    if (await File(candidate).exists()) {
      return (available: true, staged: null);
    }
  }

  final staged = File('${Directory.current.path}/$_nativeLibraryFileName');
  if (await staged.exists()) {
    return (available: true, staged: null);
  }

  for (final candidate in _siblingStagedCandidates) {
    final source = File(candidate);
    if (await source.exists()) {
      await _copyAtomically(source, staged);
      return (available: true, staged: staged);
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
