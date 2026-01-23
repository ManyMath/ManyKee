import 'dart:io';
import 'base_command.dart';

class EditCommand extends BaseCommand {
  @override
  final name = 'edit';
  @override
  final description = 'Edit an existing entry or group';

  EditCommand() {
    argParser.addFlag(
      'group',
      help: 'Treat the target as a group instead of an entry',
      negatable: false,
    );
    argParser.addOption('name', help: 'New group name');
    argParser.addOption('title', abbr: 't', help: 'Entry title');
    argParser.addOption('user', abbr: 'u', help: 'Username');
    argParser.addOption('pass', abbr: 'w', help: 'Password');
    argParser.addOption('url', help: 'URL');
    argParser.addOption('notes', abbr: 'n', help: 'Notes');
  }

  @override
  void run() {
    if (argResults!.rest.length < 2) {
      stderr.writeln(
        'Usage: keepass_cli edit <db_path> <target_uuid_or_path> [--group --name <name>] [--title <title>] ...',
      );
      exit(64);
    }
    final dbPath = argResults!.rest[0];
    final targetLocator = argResults!.rest[1];
    final isGroup = argResults!['group'] == true;

    final db = openDatabase(dbPath);
    try {
      if (isGroup) {
        final group = resolveGroup(db, targetLocator);
        final newName = argResults?['name'] as String?;
        if (newName == null || newName.isEmpty) {
          stderr.writeln('Error: --name is required when editing a group');
          exit(64);
        }

        final oldName = group.name;
        group.name = newName;
        saveDatabase(db, dbPath);

        if (isJson) {
          formatOutput({
            'success': true,
            'type': 'group',
            'uuid': group.uuid,
            'name': group.name,
            'previous_name': oldName,
            'modified': oldName != group.name,
          });
        } else {
          stdout.writeln(
              'Successfully renamed group: $oldName -> ${group.name} (${group.uuid})');
        }
      } else {
        final entry = resolveEntry(db, targetLocator);

        bool modified = false;
        if (argResults?['title'] != null) {
          entry.setField('Title', argResults?['title']);
          modified = true;
        }
        if (argResults?['user'] != null) {
          entry.setField('UserName', argResults?['user']);
          modified = true;
        }
        if (argResults?['pass'] != null) {
          entry.setField('Password', argResults?['pass'], protected: true);
          modified = true;
        }
        if (argResults?['url'] != null) {
          entry.setField('URL', argResults?['url']);
          modified = true;
        }
        if (argResults?['notes'] != null) {
          entry.setField('Notes', argResults?['notes']);
          modified = true;
        }

        if (modified) {
          saveDatabase(db, dbPath);
        }

        if (isJson) {
          formatOutput({
            'success': true,
            'type': 'entry',
            'uuid': entry.uuid,
            'title': entry.title,
            'modified': modified,
          });
        } else {
          if (modified) {
            stdout.writeln(
                'Successfully updated entry: ${entry.title} (${entry.uuid})');
          } else {
            stdout.writeln(
                'No changes specified for entry: ${entry.title} (${entry.uuid})');
          }
        }
      }
    } finally {
      db.close();
    }
  }
}
