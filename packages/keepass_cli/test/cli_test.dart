import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;

void main() {
  final cliPath = p.join(Directory.current.path, 'bin', 'keepass_cli.dart');
  final fixtureDir = p.join(Directory.current.path, '..', '..', 'rust',
      'keepass-rs', 'tests', 'resources');
  final testVaultPath =
      p.join(fixtureDir, 'test_db_kdbx4_with_password_argon2id.kdbx');
  final totpVaultPath =
      p.join(fixtureDir, 'test_db_kdbx4_with_totp_entry.kdbx');

  late File tempVault;
  late File mergeVault;
  final password = 'demopass';
  final totpPassword = 'test';

  setUp(() async {
    final original = File(testVaultPath);
    final tempDir = await Directory.systemTemp.createTemp('keepass_cli_test_');
    tempVault = File(p.join(tempDir.path, 'test.kdbx'));
    await original.copy(tempVault.path);

    mergeVault = File(p.join(tempDir.path, 'merge.kdbx'));
    await original.copy(mergeVault.path);
  });

  tearDown(() async {
    if (await tempVault.parent.exists()) {
      await tempVault.parent.delete(recursive: true);
    }
  });

  Future<ProcessResult> runCli(List<String> args) async {
    final result = await Process.run('dart', [cliPath, ...args]);
    return result;
  }

  Future<List<dynamic>> lsJson(String path,
      {required String password, String? group}) async {
    final args = ['ls', path, '--password', password, '--json'];
    if (group != null) {
      args.addAll(['--group', group]);
    }
    final result = await runCli(args);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    return json.decode(result.stdout as String) as List<dynamic>;
  }

  test('info command', () async {
    final result =
        await runCli(['info', tempVault.path, '--password', password]);
    expect(result.exitCode, 0);
    expect(result.stdout, contains('Database:'));
    expect(result.stdout, contains('Groups:'));
    expect(result.stdout, contains('Entries:'));
  });

  test('info command --json', () async {
    final result = await runCli(
        ['info', tempVault.path, '--password', password, '--json']);
    expect(result.exitCode, 0);
    final data = json.decode(result.stdout) as Map<String, dynamic>;
    expect(data['path'], contains('test.kdbx'));
    expect(data['total_groups'], isNotNull);
    expect(data['total_entries'], isNotNull);
  });

  test('ls command', () async {
    final result = await runCli(['ls', tempVault.path, '--password', password]);
    expect(result.exitCode, 0);
    expect(result.stdout, contains('Group: Root'));
  });

  test('add group and entry', () async {
    // Add group
    final groupResult = await runCli([
      'add',
      'group',
      tempVault.path,
      'New Group',
      '--password',
      password,
      '--json'
    ]);
    expect(groupResult.exitCode, 0);
    final groupData = json.decode(groupResult.stdout) as Map<String, dynamic>;
    final groupUuid = groupData['uuid'];
    expect(groupUuid, isNotNull);

    // Add entry to that group
    final entryResult = await runCli([
      'add',
      'entry',
      tempVault.path,
      '--password',
      password,
      '--parent',
      groupUuid,
      '--title',
      'New Entry',
      '--user',
      'new-user',
      '--pass',
      'new-pass',
      '--json'
    ]);
    expect(entryResult.exitCode, 0);
    final entryData = json.decode(entryResult.stdout) as Map<String, dynamic>;
    expect(entryData['uuid'], isNotNull);
    expect(entryData['title'], 'New Entry');

    // Verify with ls
    final lsResult = await runCli(
        ['ls', tempVault.path, '--password', password, '--group', groupUuid]);
    expect(lsResult.exitCode, 0);
    expect(lsResult.stdout, contains('New Entry'));
  });

  test('edit entry', () async {
    final lsData = await lsJson(tempVault.path, password: password);
    final entryUuid = lsData.firstWhere((e) => e['type'] == 'entry')['uuid'];

    final editResult = await runCli([
      'edit',
      tempVault.path,
      entryUuid,
      '--password',
      password,
      '--title',
      'Edited Title',
      '--json'
    ]);
    expect(editResult.exitCode, 0);

    final showResult = await runCli([
      'show',
      tempVault.path,
      '--entry',
      entryUuid,
      '--password',
      password,
      '--json'
    ]);
    final showData = json.decode(showResult.stdout) as Map<String, dynamic>;
    expect(showData['fields']['Title'], 'Edited Title');
  });

  test('edit group by path', () async {
    final groupResult = await runCli([
      'add',
      'group',
      tempVault.path,
      'Old Group',
      '--password',
      password,
      '--json',
    ]);
    final groupUuid = (json.decode(groupResult.stdout as String)
        as Map<String, dynamic>)['uuid'];

    final editResult = await runCli([
      'edit',
      tempVault.path,
      groupUuid as String,
      '--group',
      '--name',
      'Renamed Group',
      '--password',
      password,
      '--json',
    ]);
    expect(editResult.exitCode, 0, reason: editResult.stderr.toString());

    final groups = await lsJson(tempVault.path, password: password);
    expect(
      groups.any(
          (item) => item['type'] == 'group' && item['name'] == 'Renamed Group'),
      isTrue,
    );
  });

  test('edit group by name path falls back from UUID resolution', () async {
    final groupResult = await runCli([
      'add',
      'group',
      tempVault.path,
      'Path Group',
      '--password',
      password,
      '--json',
    ]);
    expect(groupResult.exitCode, 0, reason: groupResult.stderr.toString());

    final editResult = await runCli([
      'edit',
      tempVault.path,
      'Path Group',
      '--group',
      '--name',
      'Renamed Via Path',
      '--password',
      password,
      '--json',
    ]);
    expect(editResult.exitCode, 0, reason: editResult.stderr.toString());

    final groups = await lsJson(tempVault.path, password: password);
    expect(
      groups.any((item) =>
          item['type'] == 'group' && item['name'] == 'Renamed Via Path'),
      isTrue,
    );
  });

  test('show entry by name path falls back from UUID resolution', () async {
    final groupResult = await runCli([
      'add',
      'group',
      tempVault.path,
      'Path Parent',
      '--password',
      password,
      '--json',
    ]);
    final groupUuid = (json.decode(groupResult.stdout as String)
        as Map<String, dynamic>)['uuid'] as String;

    final addEntryResult = await runCli([
      'add',
      'entry',
      tempVault.path,
      '--password',
      password,
      '--parent',
      groupUuid,
      '--title',
      'Path Entry',
      '--user',
      'path-user',
      '--pass',
      'path-pass',
      '--json',
    ]);
    expect(addEntryResult.exitCode, 0,
        reason: addEntryResult.stderr.toString());

    final showResult = await runCli([
      'show',
      tempVault.path,
      'Path Parent/Path Entry',
      '--password',
      password,
      '--json',
    ]);
    expect(showResult.exitCode, 0, reason: showResult.stderr.toString());
    final data =
        json.decode(showResult.stdout as String) as Map<String, dynamic>;
    expect(data['title'], 'Path Entry');
  });

  test('move group', () async {
    final g1Res = await runCli([
      'add',
      'group',
      tempVault.path,
      'G1',
      '--password',
      password,
      '--json'
    ]);
    final g2Res = await runCli([
      'add',
      'group',
      tempVault.path,
      'G2',
      '--password',
      password,
      '--json'
    ]);
    final g1Uuid = json.decode(g1Res.stdout)['uuid'];
    final g2Uuid = json.decode(g2Res.stdout)['uuid'];

    final moveRes = await runCli([
      'move',
      tempVault.path,
      g2Uuid,
      g1Uuid,
      '--password',
      password,
      '--json'
    ]);
    expect(moveRes.exitCode, 0);

    final lsData =
        await lsJson(tempVault.path, password: password, group: g1Uuid);
    expect(
        lsData.any((g) => g['type'] == 'group' && g['uuid'] == g2Uuid), isTrue);
  });

  test('rm entry', () async {
    final addRes = await runCli([
      'add',
      'entry',
      tempVault.path,
      '--password',
      password,
      '--title',
      'To Delete',
      '--json'
    ]);
    final entryUuid = json.decode(addRes.stdout)['uuid'];

    final rmRes = await runCli(
        ['rm', tempVault.path, entryUuid, '--password', password, '--json']);
    expect(rmRes.exitCode, 0);

    final lsData = await lsJson(tempVault.path, password: password);
    expect(lsData.any((e) => e['uuid'] == entryUuid), isFalse);
  });

  test('show masks password by default and reveals explicit field when asked',
      () async {
    final lsData = await lsJson(tempVault.path, password: password);
    final entryUuid =
        lsData.firstWhere((e) => e['type'] == 'entry')['uuid'] as String;

    final masked = await runCli([
      'show',
      tempVault.path,
      entryUuid,
      '--password',
      password,
      '--json',
    ]);
    expect(masked.exitCode, 0, reason: masked.stderr.toString());
    final maskedData =
        json.decode(masked.stdout as String) as Map<String, dynamic>;
    expect(maskedData['fields']['Password'], '********');

    final revealed = await runCli([
      'show',
      tempVault.path,
      entryUuid,
      '--password',
      password,
      '--field',
      'Password',
      '--reveal',
    ]);
    expect(revealed.exitCode, 0, reason: revealed.stderr.toString());
    expect((revealed.stdout as String).trim(), 'pass');
  });

  test('show surfaces TOTP-backed entry data for TOTP fixture', () async {
    final listResult = await runCli([
      'ls',
      totpVaultPath,
      '--password',
      totpPassword,
      '--json',
    ]);
    expect(listResult.exitCode, 0, reason: listResult.stderr.toString());
    final entries = json.decode(listResult.stdout as String) as List<dynamic>;
    final entryUuid = entries.single['uuid'] as String;

    final unrevealedResult = await runCli([
      'show',
      totpVaultPath,
      entryUuid,
      '--password',
      totpPassword,
      '--totp',
      '--json',
    ]);
    expect(unrevealedResult.exitCode, 0,
        reason: unrevealedResult.stderr.toString());
    final unrevealedData =
        json.decode(unrevealedResult.stdout as String) as Map<String, dynamic>;
    final unrevealedTotp = unrevealedData['totp'];
    if (unrevealedTotp != null) {
      expect(unrevealedTotp['code'], '********');
    }

    final showResult = await runCli([
      'show',
      totpVaultPath,
      entryUuid,
      '--password',
      totpPassword,
      '--totp',
      '--reveal',
      '--json',
    ]);
    expect(showResult.exitCode, 0, reason: showResult.stderr.toString());
    final showData =
        json.decode(showResult.stdout as String) as Map<String, dynamic>;
    expect(showData['fields']['Title'], 'this entry has totp');
    expect(showData['fields']['otp'], contains('otpauth://totp/'));
    final totp = showData['totp'];
    if (totp != null) {
      expect(totp['code'], matches(r'^\d{6}$'));
      expect(totp['valid_for'], isNonNegative);
    }
  });

  test('merge command writes merged database', () async {
    final outputPath = p.join(tempVault.parent.path, 'merged.kdbx');
    final result = await runCli([
      'merge',
      '--db1',
      tempVault.path,
      '--db2',
      mergeVault.path,
      '--out',
      outputPath,
      '--password1',
      password,
      '--password2',
      password,
      '--json',
    ]);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(File(outputPath).existsSync(), isTrue);
    final mergeData =
        json.decode(result.stdout as String) as Map<String, dynamic>;
    expect(mergeData['total_changes'], isA<int>());
  });

  test('merge rejects unsupported --keyfile flag', () async {
    final outputPath = p.join(tempVault.parent.path, 'merged.kdbx');
    final result = await runCli([
      'merge',
      '--db1',
      tempVault.path,
      '--db2',
      mergeVault.path,
      '--out',
      outputPath,
      '--password1',
      password,
      '--password2',
      password,
      '--keyfile',
      '/nonexistent.key',
    ]);

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('does not support --keyfile'));
    expect(File(outputPath).existsSync(), isFalse);
  });

  test('rm of the root group surfaces the real error instead of "not found"',
      () async {
    final infoResult = await runCli(
        ['info', tempVault.path, '--password', password, '--json']);
    expect(infoResult.exitCode, 0, reason: infoResult.stderr.toString());
    final rootUuid = (json.decode(infoResult.stdout as String)
        as Map<String, dynamic>)['root_uuid'] as String;

    final result = await runCli([
      'rm',
      tempVault.path,
      '--password',
      password,
      rootUuid,
      '--permanent',
    ]);

    // The root group is a real, valid group UUID, so the failure must be
    // .delete()'s own error, not the generic "not found" fallback message.
    expect(result.exitCode, isNot(0));
    expect(result.stderr, isNot(contains('not found as group or entry')));
  });

  test('rm of an unknown UUID reports it as not found', () async {
    final result = await runCli([
      'rm',
      tempVault.path,
      '--password',
      password,
      '00000000-0000-0000-0000-000000000000',
    ]);
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('not found as group or entry'));
  });

  test('invalid password returns error', () async {
    final result =
        await runCli(['info', tempVault.path, '--password', 'wrong-password']);
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('Incorrect key'));
  });

  test('missing file returns error', () async {
    final missingPath = p.join(tempVault.parent.path, 'missing.kdbx');
    final result = await runCli(['info', missingPath, '--password', password]);
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('No such file or directory'));
  });
}
