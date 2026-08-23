import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// Canonical fixture password provenance: `FIXTURE_PASSWORD` in
// `rust/keepassxc/tests/bidirectional_parity.rs`.
const String _fixturePassword = 'manykee-fixture-password';

const String _fixtureSubdir = 'fixtures/compat/official/keepassxc/2.7.12';
const String _requireEnvVar = 'MANYKEE_REQUIRE_OFFICIAL_TOOLS';

void main() {
  final cliPath = p.join(Directory.current.path, 'bin', 'keepass_cli.dart');
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

  group(' official fixture smoke (read-only)', () {
    test('info --json on keepassxc-password-basic.kdbx', () async {
      await _runSmoke(
        fixtureName: 'keepassxc-password-basic.kdbx',
        stagedLibrary: stagedLibrary,
        cliPath: cliPath,
        invoke: (tempFile) async {
          final result = await Process.run('dart', [
            cliPath,
            'info',
            tempFile.path,
            '--password',
            _fixturePassword,
            '--json',
          ]);
          expect(result.exitCode, 0,
              reason: 'stdout: ${result.stdout}\nstderr: ${result.stderr}');
          final data =
              json.decode(result.stdout as String) as Map<String, dynamic>;
          expect(data['path'], contains('keepassxc-password-basic.kdbx'));
          expect(data['root_uuid'], isA<String>());
          expect((data['root_uuid'] as String), isNotEmpty);
          expect(data['total_groups'], isA<int>());
          expect(data['total_entries'], isA<int>());
        },
      );
    });

    test('ls --json on keepassxc-password-basic.kdbx', () async {
      await _runSmoke(
        fixtureName: 'keepassxc-password-basic.kdbx',
        stagedLibrary: stagedLibrary,
        cliPath: cliPath,
        invoke: (tempFile) async {
          final result = await Process.run('dart', [
            cliPath,
            'ls',
            tempFile.path,
            '--password',
            _fixturePassword,
            '--json',
          ]);
          expect(result.exitCode, 0,
              reason: 'stdout: ${result.stdout}\nstderr: ${result.stderr}');
          final data = json.decode(result.stdout as String) as List<dynamic>;
          final hasContent = data.isNotEmpty;
          expect(hasContent, isTrue,
              reason: 'ls should list at least one group or entry');
          for (final item in data) {
            final map = item as Map<String, dynamic>;
            expect(map['type'], anyOf('group', 'entry'));
            expect(map['uuid'], isA<String>());
            expect((map['uuid'] as String), isNotEmpty);
          }
        },
      );
    });

    test('show --json surfaces an entry from keepassxc-password-basic.kdbx',
        () async {
      await _runSmoke(
        fixtureName: 'keepassxc-password-basic.kdbx',
        stagedLibrary: stagedLibrary,
        cliPath: cliPath,
        invoke: (tempFile) async {
          // Locate an entry UUID via ls --json (read-only). The KeePassXC
          // basic fixture nests entries inside a top-level subgroup, so
          // descend one level when root-level has only groups.
          final entryUuid = await _findAnyEntryUuid(
            cliPath: cliPath,
            tempFile: tempFile,
          );
          if (entryUuid == null) {
            // Shape guard: regeneration should never leave this fixture
            // empty. Skip explicitly rather than silently passing.
            markTestSkipped(
                'keepassxc-password-basic.kdbx exposes no entry via ls');
            return;
          }
          final showResult = await Process.run('dart', [
            cliPath,
            'show',
            tempFile.path,
            entryUuid,
            '--password',
            _fixturePassword,
            '--json',
          ]);
          expect(showResult.exitCode, 0,
              reason: 'show stdout: ${showResult.stdout}\n'
                  'show stderr: ${showResult.stderr}');
          final data =
              json.decode(showResult.stdout as String) as Map<String, dynamic>;
          expect(data['uuid'], entryUuid);
          expect(data['fields'], isA<Map>());
          // Password must be masked by default (no --reveal passed).
          final fields = data['fields'] as Map<String, dynamic>;
          if (fields.containsKey('Password')) {
            expect(fields['Password'], '********');
          }
        },
      );
    });
  });
}

/// Locates any entry UUID in the database via read-only `ls --json`
/// invocations. Descends at most one level into the first subgroup when
/// the root listing returns only groups: enough for the basic fixture's
/// `Fixtures/BasicEntry` shape without assuming exact names.
Future<String?> _findAnyEntryUuid({
  required String cliPath,
  required File tempFile,
}) async {
  Future<List<Map<String, dynamic>>> ls(String? groupUuid) async {
    final args = [
      cliPath,
      'ls',
      tempFile.path,
      '--password',
      _fixturePassword,
      '--json',
      if (groupUuid != null) ...['--group', groupUuid],
    ];
    final result = await Process.run('dart', args);
    expect(result.exitCode, 0,
        reason: 'ls stdout: ${result.stdout}\nls stderr: ${result.stderr}');
    return (json.decode(result.stdout as String) as List<dynamic>)
        .cast<Map<String, dynamic>>();
  }

  final rootListing = await ls(null);
  final rootEntry = rootListing.firstWhere(
    (item) => item['type'] == 'entry',
    orElse: () => <String, dynamic>{},
  );
  if (rootEntry.isNotEmpty) {
    return rootEntry['uuid'] as String;
  }

  for (final item in rootListing.where((i) => i['type'] == 'group')) {
    final nested = await ls(item['uuid'] as String);
    final nestedEntry = nested.firstWhere(
      (i) => i['type'] == 'entry',
      orElse: () => <String, dynamic>{},
    );
    if (nestedEntry.isNotEmpty) {
      return nestedEntry['uuid'] as String;
    }
  }
  return null;
}

Future<void> _runSmoke({
  required String fixtureName,
  required File? stagedLibrary,
  required String cliPath,
  required Future<void> Function(File tempFile) invoke,
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

  // Copy fixture into a tempdir before invoking the CLI as belt-and-braces
  // against any accidental write: read-only subcommands only, but the
  // original committed fixture is never touched regardless.
  final tempDir =
      await Directory.systemTemp.createTemp('keepass_cli_official_');
  try {
    final tempFile = File(p.join(tempDir.path, fixtureName));
    await File(fixturePath).copy(tempFile.path);

    final originalBytes = await File(fixturePath).readAsBytes();
    final copyBytesBefore = await tempFile.readAsBytes();

    await invoke(tempFile);

    // Verify the fixture (and the tempdir copy) are byte-identical after
    // the read-only invocation: no mutation should have occurred.
    final copyBytesAfter = await tempFile.readAsBytes();
    expect(copyBytesAfter, orderedEquals(copyBytesBefore),
        reason: 'read-only subcommand mutated the tempdir copy');
    final originalBytesAfter = await File(fixturePath).readAsBytes();
    expect(originalBytesAfter, orderedEquals(originalBytes),
        reason: 'committed fixture was mutated by the CLI invocation');
  } finally {
    await tempDir.delete(recursive: true);
  }
}

/// Climbs from the current working directory up to 6 levels looking for
/// `fixtures/compat/official/keepassxc/2.7.12/<name>`. Returns the absolute
/// path on success, or null if not found. Mirrors the helper in
/// `packages/keepass/test/official_fixture_smoke_test.dart`.
String? _findOfficialFixture(String name) {
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    final candidate = File(p.join(dir.path, _fixtureSubdir, name));
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
/// the CLI subprocess (which inherits that CWD) can load it. Returns the
/// staged file, or null if no source `.so` was found. Mirrors the helper in
/// `packages/keepass/test/official_fixture_smoke_test.dart`.
Future<File?> _tryStageNativeLibrary() async {
  final stagedPath = p.join(Directory.current.path, 'libkeepassxc_ffi.so');
  final staged = File(stagedPath);
  if (await staged.exists()) {
    return staged;
  }

  final candidates = <String>[
    '../keepass/libkeepassxc_ffi.so',
    '../../packages/keepass/libkeepassxc_ffi.so',
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
