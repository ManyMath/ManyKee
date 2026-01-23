import 'dart:io';
import 'base_command.dart';

class LsCommand extends BaseCommand {
  @override
  final name = 'ls';
  @override
  final description = 'List groups and entries';

  LsCommand() {
    argParser.addOption(
      'group',
      abbr: 'g',
      help: 'Group UUID or path to list (defaults to root)',
    );
  }

  @override
  void run() {
    if (argResults!.rest.isEmpty) {
      stderr.writeln('Error: Database path is required');
      stderr.writeln('Usage: keepass_cli ls <database_path> [-g <group_uuid>]');
      exit(64);
    }
    final dbPath = argResults!.rest.first;
    final db = openDatabase(dbPath);
    try {
      final groupUuid = argResults?['group'] as String?;
      final group = resolveGroup(db, groupUuid);

      final groups = group.groups
          .map((g) => {
                'type': 'group',
                'name': g.name,
                'uuid': g.uuid,
              })
          .toList();

      final entries = group.entries
          .map((e) => {
                'type': 'entry',
                'title': e.title ?? '',
                'user': e.userName ?? '',
                'uuid': e.uuid,
              })
          .toList();

      final results = [...groups, ...entries];

      if (isJson) {
        formatOutput(results);
      } else {
        stdout.writeln('Group: ${group.name} (${group.uuid})');
        for (final g in groups) {
          stdout.writeln('[DIR] ${g['name']} (${g['uuid']})');
        }
        for (final e in entries) {
          stdout.writeln('      ${e['title']} (${e['uuid']}) - ${e['user']}');
        }
      }
    } finally {
      db.close();
    }
  }
}
