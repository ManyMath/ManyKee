import 'dart:io';
import 'package:args/command_runner.dart';

// MergeCommand will be implemented in Plan 04
void main(List<String> args) async {
  final runner = CommandRunner('keepass_cli', 'KeePass database CLI tool');
  // runner.addCommand(MergeCommand());

  try {
    await runner.run(args);
  } on UsageException catch (e) {
    stderr.writeln(e);
    exit(64);
  }
}
