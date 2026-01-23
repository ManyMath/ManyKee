import 'dart:io';
import 'base_command.dart';

class ShowCommand extends BaseCommand {
  @override
  final name = 'show';
  @override
  final description = 'Display entry fields and TOTP';

  ShowCommand() {
    argParser.addOption('entry', abbr: 'e', help: 'Entry UUID or path to show');
    argParser.addOption('field', abbr: 'f', help: 'Print only one field value');
    argParser.addFlag('totp', help: 'Show TOTP code', negatable: false);
    argParser.addFlag('reveal',
        abbr: 'r', help: 'Reveal password', negatable: false);
  }

  @override
  void run() {
    if (argResults!.rest.isEmpty) {
      stderr.writeln('Error: Database path is required');
      stderr.writeln(
        'Usage: keepass_cli show <database_path> [<entry_uuid_or_path>] [--entry <entry_uuid_or_path>] [--field <name>] [--totp] [-r]',
      );
      exit(64);
    }
    final dbPath = argResults!.rest.first;
    final entryLocator = argResults!['entry'] as String? ??
        (argResults!.rest.length > 1 ? argResults!.rest[1] : null);
    if (entryLocator == null || entryLocator.isEmpty) {
      stderr.writeln('Error: Entry UUID or path is required');
      exit(64);
    }

    final db = openDatabase(dbPath);
    try {
      final entry = resolveEntry(db, entryLocator);
      final payload = entry.readFields();
      final fields = Map<String, dynamic>.from(
        (payload['fields'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      );
      final customData = Map<String, dynamic>.from(
        (payload['custom_data'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      );
      final revealPassword = argResults!['reveal'] == true;
      final fieldName = argResults!['field'] as String?;
      final includeTotp = argResults!['totp'] == true;
      Map<String, dynamic>? totp;

      if (includeTotp) {
        totp = entry.getTotpCode();
      }

      if (!revealPassword && fields.containsKey('Password')) {
        fields['Password'] = '********';
      }

      if (fieldName != null) {
        final value = fields[fieldName];
        if (value == null) {
          stderr.writeln('Error: Field not found: $fieldName');
          exit(1);
        }
        if (isJson) {
          formatOutput({
            'uuid': entry.uuid,
            'field': fieldName,
            'value': value,
          });
        } else {
          stdout.writeln(value);
        }
        return;
      }

      final result = <String, dynamic>{
        'uuid': entry.uuid,
        'title': fields['Title'],
        'fields': fields,
        'custom_data': customData,
      };
      if (totp != null) {
        result['totp'] = totp;
      }

      if (isJson) {
        formatOutput(result);
      } else {
        stdout.writeln('Entry: ${fields['Title'] ?? entry.uuid}');
        for (final entryField in fields.entries) {
          stdout.writeln('  ${entryField.key}: ${entryField.value}');
        }
        if (customData.isNotEmpty) {
          stdout.writeln('  Custom Data:');
          for (final item in customData.entries) {
            stdout.writeln('    ${item.key}: ${item.value}');
          }
        }
        if (totp != null) {
          final validFor = totp['valid_for'] ?? totp['expires_in'];
          final period = totp['period'];
          final suffix = validFor == null
              ? ''
              : period == null
                  ? ' (${validFor}s remaining)'
                  : ' (${validFor}s remaining of ${period}s)';
          stdout.writeln('  TOTP: ${totp['code']}$suffix');
        }
      }
    } finally {
      db.close();
    }
  }
}
