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

      // Resolve which kind of object this UUID refers to first, so a real
      // failure from .delete() itself (e.g. deleting the root group) isn't
      // misreported as "not found" by falling through to the entry branch.
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
        group.delete(permanent: permanent);
      } else {
        Entry(db, uuid).delete(permanent: permanent);
      }
      deleted = true;
      type = resolvedType;

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
