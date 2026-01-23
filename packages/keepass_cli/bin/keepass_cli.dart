import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:keepass_cli/keepass_cli.dart';

void main(List<String> args) async {
  final runner = CommandRunner('keepass_cli', 'KeePass database CLI tool')
    ..addCommand(MergeCommand())
    ..addCommand(InfoCommand())
    ..addCommand(LsCommand())
    ..addCommand(ShowCommand())
    ..addCommand(AddCommand())
    ..addCommand(EditCommand())
    ..addCommand(RmCommand())
    ..addCommand(MoveCommand())
    ..addCommand(YubiKeyCommand());

  try {
    await runner.run(args);
  } on UsageException catch (e) {
    stderr.writeln(e);
    exit(64);
  } catch (e) {
    stderr.writeln('Error: $e');
    exit(1);
  }
}
