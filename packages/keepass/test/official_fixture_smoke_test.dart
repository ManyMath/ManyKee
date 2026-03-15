import 'dart:io';

import 'package:keepass/keepass.dart';
import 'package:test/test.dart';

// Canonical fixture password provenance: `FIXTURE_PASSWORD` in
// `rust/keepassxc/tests/bidirectional_parity.rs`.
const String _fixturePassword = 'manykee-fixture-password';

const String _fixtureSubdir = 'fixtures/compat/official/keepassxc/2.7.12';
const String _requireEnvVar = 'MANYKEE_REQUIRE_OFFICIAL_TOOLS';

void main() {
  File? stagedLibrary;

  setUpAll(() async {
    stagedLibrary = await _tryStageNativeLibrary();
  });

  tearDownAll(() async {
    final staged = stagedLibrary;
    if (staged != null && await staged.exists()) {
      await staged.delete();
    }
  });

  test('keepassxc-password-basic.kdbx unlocks via Database.open', () async {
    await _runSmoke(
      fixtureName: 'keepassxc-password-basic.kdbx',
      stagedLibrary: stagedLibrary,
    );
  });

  test('keepassxc-richcontent.kdbx unlocks via Database.open', () async {
    await _runSmoke(
      fixtureName: 'keepassxc-richcontent.kdbx',
      stagedLibrary: stagedLibrary,
    );
  });
}

Future<void> _runSmoke({
  required String fixtureName,
  required File? stagedLibrary,
}) async {
  final required = Platform.environment[_requireEnvVar] == '1';

  if (stagedLibrary == null) {
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

/// Stages `libkeepassxc_ffi.so` next to the Dart test runner's CWD so that
/// `native_library.dart` can load it. Returns the staged file, or null if
/// no source `.so` was found. Mirrors the pattern in
/// `packages/keepass_flutter/test/native_vault_state_test.dart::_stageNativeLibrary`.
Future<File?> _tryStageNativeLibrary() async {
  final stagedPath = '${Directory.current.path}/libkeepassxc_ffi.so';
  final staged = File(stagedPath);
  if (await staged.exists()) {
    return staged;
  }

  final candidates = <String>[
    '../keepass_cli/libkeepassxc_ffi.so',
    '../../packages/keepass_cli/libkeepassxc_ffi.so',
    '../../rust/target/debug/libkeepassxc_ffi.so',
    'rust/target/debug/libkeepassxc_ffi.so',
  ];

  for (final candidate in candidates) {
    final source = File(candidate);
    if (await source.exists()) {
      await source.copy(staged.path);
      return staged;
    }
  }

  return null;
}
