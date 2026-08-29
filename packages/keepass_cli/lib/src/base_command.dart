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
    argParser.addOption('password',
        abbr: 'p',
        help: 'Database password (visible in ps). '
            'Prefer the KEEPASS_PASSWORD env var or the interactive prompt.');
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
      final keyFile = _keyFile;
      final slot = _yubikeySlot;
      if (keyFile != null && slot != null) {
        return Database.openWithKeyFileAndYubiKey(
          path,
          password: _password!,
          keyFilePath: keyFile,
          slot: slot,
          serial: _yubikeySerial ?? 0,
        );
      } else if (slot != null) {
        return Database.openWithYubiKey(
          path,
          password: _password!,
          slot: slot,
          serial: _yubikeySerial ?? 0,
        );
      } else if (keyFile != null) {
        return Database.openWithKeyFile(path,
            password: _password!, keyFilePath: keyFile);
      } else {
        return Database.open(path, password: _password!);
      }
    } on KeePassError catch (e) {
      stderr.writeln('Error: ${e.message}');
      exit(1);
    }
  }

  void saveDatabase(Database db, String path) {
    // Save with exactly the factors the database was opened with so a write
    // never silently re-keys the vault to password-only.
    try {
      final keyFile = _keyFile;
      final slot = _yubikeySlot;
      if (keyFile != null && slot != null) {
        db.saveWithKeyFileAndYubiKey(
          path,
          password: _password!,
          keyFilePath: keyFile,
          slot: slot,
          serial: _yubikeySerial ?? 0,
        );
      } else if (slot != null) {
        db.saveWithYubiKey(
          path,
          password: _password!,
          slot: slot,
          serial: _yubikeySerial ?? 0,
        );
      } else if (keyFile != null) {
        db.saveWithKeyFile(path, password: _password!, keyFilePath: keyFile);
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
      final group = Group(db, trimmed);
      group.name; // Force FFI validation that this UUID actually exists.
      return group;
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
      final entry = Entry(db, trimmed);
      entry
          .readFields(); // Force FFI validation that this UUID actually exists.
      return entry;
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
