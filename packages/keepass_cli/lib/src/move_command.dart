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
      stderr.writeln(
          'Usage: keepass_cli move <db_path> <uuid> <target_parent_uuid>');
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

      // Resolve which kind of object this UUID refers to first, so a real
      // failure from .move() itself isn't misreported as "not found" by
      // falling through to the entry branch.
      String? resolvedType;
      final group = Group(db, uuid);
      try {
        name = group.name; // Throws if not a valid group UUID.
        resolvedType = 'group';
      } catch (_) {
        final entry = Entry(db, uuid);
        try {
          name = entry.title ?? 'Untitled'; // Throws if not a valid entry UUID.
          resolvedType = 'entry';
        } catch (_) {
          stderr.writeln('Error: UUID $uuid not found as group or entry');
          exit(1);
        }
      }

      if (resolvedType == 'group') {
        group.move(targetParentUuid);
      } else {
        Entry(db, uuid).move(targetParentUuid);
      }
      moved = true;
      type = resolvedType;

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
          stdout.writeln(
              'Successfully moved $type: $name ($uuid) to $targetParentUuid');
        }
      }
    } finally {
      db.close();
    }
  }
}
