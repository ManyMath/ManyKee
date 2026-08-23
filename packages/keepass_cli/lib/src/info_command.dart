import 'dart:io';
import 'package:keepass/keepass.dart';
import 'base_command.dart';

class InfoCommand extends BaseCommand {
  @override
  final name = 'info';
  @override
  final description = 'Show database metadata';

  InfoCommand() {}

  @override
  void run() {
    if (argResults!.rest.isEmpty) {
      stderr.writeln('Error: Database path is required');
      stderr.writeln('Usage: keepass_cli info <database_path>');
      exit(64);
    }
    final dbPath = argResults!.rest.first;
    final db = openDatabase(dbPath);
    try {
      final root = db.rootGroup;
      final info = {
        'path': dbPath,
        'root_name': root.name,
        'root_uuid': root.uuid,
        'total_groups': _countGroups(root),
        'total_entries': _countEntries(root),
      };

      if (isJson) {
        formatOutput(info);
      } else {
        stdout.writeln('Database: ${info['path']}');
        stdout.writeln('Root Name: ${info['root_name']}');
        stdout.writeln('Root UUID: ${info['root_uuid']}');
        stdout.writeln('Groups: ${info['total_groups']}');
        stdout.writeln('Entries: ${info['total_entries']}');
      }
    } finally {
      db.close();
    }
  }

  int _countGroups(Group group) {
    final subGroups = group.groups;
    int count = subGroups.length;
    for (final child in subGroups) {
      count += _countGroups(child);
    }
    return count;
  }

  int _countEntries(Group group) {
    int count = group.entryCount;
    for (final child in group.groups) {
      count += _countEntries(child);
    }
    return count;
  }
}
