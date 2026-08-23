import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:keepass/keepass.dart';
import 'base_command.dart';

class AddCommand extends Command {
  @override
  final name = 'add';
  @override
  final description = 'Add a new group or entry';

  AddCommand() {
    addSubcommand(AddGroupSubcommand());
    addSubcommand(AddEntrySubcommand());
  }
}

class AddGroupSubcommand extends BaseCommand {
  @override
  final name = 'group';
  @override
  final description = 'Add a new group';

  AddGroupSubcommand() {
    argParser.addOption('parent',
        abbr: 'a', help: 'Parent group UUID (defaults to root)');
  }

  @override
  void run() {
    if (argResults!.rest.isEmpty) {
      stderr.writeln(
          'Usage: keepass_cli add group <db_path> <group_name> [--parent <uuid>]');
      exit(64);
    }
    final dbPath = argResults!.rest[0];
    if (argResults!.rest.length < 2) {
      stderr.writeln('Error: Group name is required');
      exit(64);
    }
    final groupName = argResults!.rest[1];

    final db = openDatabase(dbPath);
    try {
      final parentUuid = argResults?['parent'] as String?;
      final parent = parentUuid != null ? Group(db, parentUuid) : db.rootGroup;

      final newGroup = parent.createGroup(groupName);

      saveDatabase(db, dbPath);

      if (isJson) {
        formatOutput({
          'success': true,
          'type': 'group',
          'uuid': newGroup.uuid,
          'name': newGroup.name,
        });
      } else {
        stdout.writeln(
            'Successfully created group: ${newGroup.name} (${newGroup.uuid})');
      }
    } finally {
      db.close();
    }
  }
}

class AddEntrySubcommand extends BaseCommand {
  @override
  final name = 'entry';
  @override
  final description = 'Add a new entry';

  AddEntrySubcommand() {
    argParser.addOption('parent',
        abbr: 'a', help: 'Parent group UUID (defaults to root)');
    argParser.addOption('title', abbr: 't', help: 'Entry title');
    argParser.addOption('user', abbr: 'u', help: 'Username');
    argParser.addOption('pass', abbr: 'w', help: 'Password (visible in ps)');
    argParser.addOption('url', help: 'URL');
    argParser.addOption('notes', abbr: 'n', help: 'Notes');
  }

  @override
  void run() {
    if (argResults!.rest.isEmpty) {
      stderr.writeln(
          'Usage: keepass_cli add entry <db_path> [--parent <uuid>] [--title <title>] ...');
      exit(64);
    }
    final dbPath = argResults!.rest[0];

    final db = openDatabase(dbPath);
    try {
      final parentUuid = argResults?['parent'] as String?;
      final parent = parentUuid != null ? Group(db, parentUuid) : db.rootGroup;

      final entry = parent.createEntry();

      if (argResults?['title'] != null)
        entry.setField('Title', argResults?['title']);
      if (argResults?['user'] != null)
        entry.setField('UserName', argResults?['user']);
      if (argResults?['pass'] != null)
        entry.setField('Password', argResults?['pass'], protected: true);
      if (argResults?['url'] != null) entry.setField('URL', argResults?['url']);
      if (argResults?['notes'] != null)
        entry.setField('Notes', argResults?['notes']);

      saveDatabase(db, dbPath);

      if (isJson) {
        formatOutput({
          'success': true,
          'type': 'entry',
          'uuid': entry.uuid,
          'title': entry.title,
        });
      } else {
        stdout.writeln(
            'Successfully created entry: ${entry.title} (${entry.uuid})');
      }
    } finally {
      db.close();
    }
  }
}
