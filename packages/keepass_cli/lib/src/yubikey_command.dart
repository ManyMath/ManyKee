import 'dart:io';
import 'package:keepass/keepass.dart';
import 'base_command.dart';

class YubiKeyCommand extends BaseCommand {
  @override
  final name = 'yubikey';
  @override
  final description = 'YubiKey management and operations';

  YubiKeyCommand() {
    addSubcommand(YubiKeyListCommand());
    addSubcommand(YubiKeyUnlockCommand());
  }
}

class YubiKeyListCommand extends BaseCommand {
  @override
  final name = 'list';
  @override
  final description = 'List connected YubiKeys';

  @override
  void run() {
    try {
      final keys = Database.listYubiKeys();
      if (isJson) {
        formatOutput(keys);
      } else {
        if (keys.isEmpty) {
          stdout.writeln('No YubiKeys found.');
        } else {
          for (final key in keys) {
            final serial = key['serial_number'] ?? key['serial'];
            stdout.writeln('YubiKey: ${key['name']} (Serial: $serial)');
          }
        }
      }
    } catch (e) {
      stderr.writeln('Error: $e');
      exit(1);
    }
  }
}

class YubiKeyUnlockCommand extends BaseCommand {
  @override
  final name = 'unlock';
  @override
  final description =
      'Unlock a database using YubiKey to verify challenge-response';

  @override
  void run() {
    if (argResults!.rest.isEmpty) {
      stderr.writeln('Error: Database path is required');
      stderr.writeln(
          'Usage: keepass_cli yubikey unlock <database_path> --yubikey-slot <slot>');
      exit(64);
    }
    final dbPath = argResults!.rest.first;
    final db = openDatabase(dbPath);
    try {
      if (isJson) {
        formatOutput({'status': 'success', 'database': dbPath});
      } else {
        stdout.writeln('Successfully unlocked $dbPath using YubiKey.');
      }
    } finally {
      db.close();
    }
  }
}
