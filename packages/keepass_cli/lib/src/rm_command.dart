import 'dart:io';
import 'package:keepass/keepass.dart';
import 'base_command.dart';

class RmCommand extends BaseCommand {
  @override
  final name = 'rm';
  @override
  final description = 'Delete a group or entry';

  RmCommand() {
    argParser.addFlag('permanent', help: 'Permanently delete (don\'t move to Trash)', negatable: false);
  }

  @override
  void run() {
    if (argResults!.rest.length < 2) {
      stderr.writeln('Usage: keepass_cli rm <db_path> <uuid> [--permanent]');
      exit(64);
    }
    final dbPath = argResults!.rest[0];
    final uuid = argResults!.rest[1];
    final permanent = argResults?['permanent'] ?? false;

    final db = openDatabase(dbPath);
    try {
      bool deleted = false;
      String type = '';
      String name = '';

      // Try as group
      try {
        final group = Group(db, uuid);
        name = group.name; // This will throw if it's not a valid group UUID
        group.delete(permanent: permanent);
        deleted = true;
        type = 'group';
      } catch (e) {
        // Not a group, try as entry
        try {
          final entry = Entry(db, uuid);
          name = entry.title ?? 'Untitled'; // This will throw if it's not a valid entry UUID
          entry.delete(permanent: permanent);
          deleted = true;
          type = 'entry';
        } catch (e2) {
          stderr.writeln('Error: UUID $uuid not found as group or entry');
          exit(1);
        }
      }

      if (deleted) {
        saveDatabase(db, dbPath);
        if (isJson) {
          formatOutput({
            'success': true,
            'type': type,
            'uuid': uuid,
            'name': name,
            'permanent': permanent,
          });
        } else {
          stdout.writeln('Successfully deleted $type: $name ($uuid)');
        }
      }
    } finally {
      db.close();
    }
  }
}
