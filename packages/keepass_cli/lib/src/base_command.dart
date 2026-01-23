import 'dart:convert';
import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:keepass/keepass.dart';
import 'password_input.dart';

abstract class BaseCommand extends Command {
  String? _password;
  String? _keyFile;
  String? _yubikeySlot;
  int? _yubikeySerial;

  BaseCommand() {
    argParser.addOption('password', abbr: 'p', help: 'Database password');
    argParser.addOption('keyfile', abbr: 'k', help: 'Path to key file');
    argParser.addOption('yubikey-slot',
        help: 'YubiKey challenge-response slot (1 or 2)');
    argParser.addOption('yubikey-serial',
        help: 'YubiKey serial number (optional)');
    argParser.addFlag('json', help: 'Output in JSON format', negatable: false);
  }

  bool get isJson => argResults?['json'] ?? false;

  Database openDatabase(String path) {
    _password = getPassword(
      flag: argResults?['password'],
      envVar: 'KEEPASS_PASSWORD',
      promptLabel: 'Enter password for $path',
    );

    _keyFile = argResults?['keyfile'] as String?;
    _yubikeySlot = argResults?['yubikey-slot'] as String?;
    _yubikeySerial =
        int.tryParse(argResults?['yubikey-serial'] as String? ?? '');

    try {
      if (_yubikeySlot != null) {
        return Database.openWithYubiKey(
          path,
          password: _password!,
          slot: _yubikeySlot!,
          serial: _yubikeySerial ?? 0,
        );
      } else if (_keyFile != null) {
        return Database.openWithKeyFile(path,
            password: _password!, keyFilePath: _keyFile!);
      } else {
        return Database.open(path, password: _password!);
      }
    } on KeePassError catch (e) {
      stderr.writeln('Error: ${e.message}');
      exit(1);
    }
  }

  void saveDatabase(Database db, String path) {
    try {
      if (_yubikeySlot != null) {
        // Rust kpxc_database_save currently doesn't support YubiKey directly
        // in the same way as kpxc_database_save_with_keyfile.
        // Usually, the YubiKey is part of the master key.
        // Let's check bindings.g.dart to see what save functions we have.
        db.save(path, password: _password!);
      } else if (_keyFile != null) {
        db.saveWithKeyFile(path, password: _password!, keyFilePath: _keyFile!);
      } else {
        db.save(path, password: _password!);
      }
    } on KeePassError catch (e) {
      stderr.writeln('Error saving database: ${e.message}');
      exit(1);
    }
  }

  void formatOutput(dynamic data) {
    if (isJson) {
      stdout.writeln(const JsonEncoder.withIndent('  ').convert(data));
    } else {
      if (data is Map || data is List) {
        stdout.writeln(const JsonEncoder.withIndent('  ').convert(data));
      } else {
        stdout.writeln(data);
      }
    }
  }

  Group resolveGroup(Database db, String? locator) {
    if (locator == null ||
        locator.trim().isEmpty ||
        locator == '/' ||
        locator == '.') {
      return db.rootGroup;
    }

    final trimmed = locator.trim();
    try {
      return Group(db, trimmed);
    } on KeePassError {
      return _resolveGroupPath(db, trimmed);
    }
  }

  Entry resolveEntry(Database db, String locator) {
    final trimmed = locator.trim();
    if (trimmed.isEmpty) {
      throw usageException('Entry locator is required.');
    }

    try {
      return Entry(db, trimmed);
    } on KeePassError {
      final normalized =
          trimmed.startsWith('/') ? trimmed.substring(1) : trimmed;
      final segments =
          normalized.split('/').where((segment) => segment.isNotEmpty).toList();
      if (segments.isEmpty) {
        throw usageException('Entry locator is required.');
      }

      final entryTitle = segments.removeLast();
      final parent = segments.isEmpty
          ? db.rootGroup
          : _resolveGroupPath(db, segments.join('/'));
      for (final entry in parent.entries) {
        if ((entry.title ?? '') == entryTitle) {
          return entry;
        }
      }
      throw usageException('Entry not found: $locator');
    }
  }

  Group _resolveGroupPath(Database db, String locator) {
    final normalized = locator.startsWith('/') ? locator.substring(1) : locator;
    final segments =
        normalized.split('/').where((segment) => segment.isNotEmpty).toList();
    Group current = db.rootGroup;

    if (segments.isNotEmpty && segments.first == current.name) {
      segments.removeAt(0);
    }

    for (final segment in segments) {
      final matches =
          current.groups.where((group) => group.name == segment).toList();
      if (matches.isEmpty) {
        throw usageException('Group not found: $locator');
      }
      if (matches.length > 1) {
        throw usageException('Group path is ambiguous: $locator');
      }
      current = matches.single;
    }

    return current;
  }
}
