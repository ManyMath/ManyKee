import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:keepass_cli/src/merge_command.dart';

void main(List<String> args) async {
 final runner = CommandRunner('keepass_cli', 'KeePass database CLI tool')
 ..addCommand(MergeCommand());

 try {
 await runner.run(args);
 } on UsageException catch (e) {
 stderr.writeln(e);
 exit(64);
 }
}
