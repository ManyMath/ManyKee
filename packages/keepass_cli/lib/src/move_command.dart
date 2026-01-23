import 'dart:io';
import 'package:keepass/keepass.dart';
import 'base_command.dart';

class MoveCommand extends BaseCommand {
  @override
  final name = 'move';
  @override
  final description = 'Move a group or entry to a new parent group';

  @override
  void run() {
    if (argResults!.rest.length < 3) {
      stderr.writeln('Usage: keepass_cli move <db_path> <uuid> <target_parent_uuid>');
      exit(64);
    }
    final dbPath = argResults!.rest[0];
    final uuid = argResults!.rest[1];
    final targetParentUuid = argResults!.rest[2];

    final db = openDatabase(dbPath);
    try {
      bool moved = false;
      String type = '';
      String name = '';

      // Try as group
      try {
        final group = Group(db, uuid);
        name = group.name; // This will throw if it's not a valid group UUID
        group.move(targetParentUuid);
        moved = true;
        type = 'group';
      } catch (e) {
        // Not a group, try as entry
        try {
          final entry = Entry(db, uuid);
          name = entry.title ?? 'Untitled'; // This will throw if it's not a valid entry UUID
          entry.move(targetParentUuid);
          moved = true;
          type = 'entry';
        } catch (e2) {
          stderr.writeln('Error: UUID $uuid not found as group or entry');
          exit(1);
        }
      }

      if (moved) {
        saveDatabase(db, dbPath);
        if (isJson) {
          formatOutput({
            'success': true,
            'type': type,
            'uuid': uuid,
            'name': name,
            'newParentUuid': targetParentUuid,
          });
        } else {
          stdout.writeln('Successfully moved $type: $name ($uuid) to $targetParentUuid');
        }
      }
    } finally {
      db.close();
    }
  }
}
