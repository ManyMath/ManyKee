import 'dart:io';
import 'package:keepass/keepass.dart';
import 'base_command.dart';
import 'password_input.dart';

class MergeCommand extends BaseCommand {
  @override
  final String name = 'merge';

  @override
  final String description = 'Merge two KDBX databases';

  MergeCommand() {
    argParser
      ..addOption('db1', mandatory: true, help: 'Path to first database')
      ..addOption('db2', mandatory: true, help: 'Path to second database')
      ..addOption('out',
          mandatory: true, help: 'Output path for merged database')
      ..addOption('password1',
          help: 'Password for first database (visible in ps)')
      ..addOption('password2',
          help: 'Password for second database (visible in ps)');
  }

  @override
  void run() {
    final db1Path = argResults!['db1'] as String;
    final db2Path = argResults!['db2'] as String;
    final outPath = argResults!['out'] as String;

    // merge only supports password-protected databases (--password1/
    // --password2 below); --password/--keyfile/--yubikey-slot/
    // --yubikey-serial are inherited from BaseCommand's shared argParser but
    // silently ignored by this command, so reject them explicitly instead of
    // letting a key-file- or YubiKey-protected database fail open with a
    // confusing decryption error.
    if (argResults!['password'] != null) {
      stderr.writeln(
          'Error: --password is not used by merge; use --password1/--password2 instead.');
      exit(1);
    }
    if (argResults!['keyfile'] != null || argResults!['yubikey-slot'] != null) {
      stderr.writeln(
          'Error: merge does not support --keyfile/--yubikey-slot; only password-protected databases can be merged.');
      exit(1);
    }

    if (!File(db1Path).existsSync()) {
      stderr.writeln('Error: File not found: $db1Path');
      exit(1);
    }
    if (!File(db2Path).existsSync()) {
      stderr.writeln('Error: File not found: $db2Path');
      exit(1);
    }

    final password1 = getPassword(
      flag: argResults!['password1'] as String?,
      envVar: 'KEEPASS_PASSWORD1',
      promptLabel: 'Password for $db1Path',
    );
    final password2 = getPassword(
      flag: argResults!['password2'] as String?,
      envVar: 'KEEPASS_PASSWORD2',
      promptLabel: 'Password for $db2Path',
    );

    Database? db1;
    Database? db2;
    try {
      db1 = Database.open(db1Path, password: password1);
      db2 = Database.open(db2Path, password: password2);
      final result = db1.merge(db2);
      db1.save(outPath, password: password1);

      if (isJson) {
        formatOutput(result.toJson());
      } else {
        stdout.writeln('Merge complete: $outPath');
        stdout.writeln(result);
      }
    } on KeePassError catch (e) {
      stderr.writeln('Error: $e');
      exit(1);
    } finally {
      db2?.close();
      db1?.close();
    }
  }
}
