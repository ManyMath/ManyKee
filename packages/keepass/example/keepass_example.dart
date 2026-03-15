// Minimal demo of `package:keepass`.
//
// Usage:
//   dart run example/keepass_example.dart <vault.kdbx> <password>
//
// The native library (`libkeepassxc_ffi.{so,dylib,dll}`) must be on the
// process's library search path. Build it from the ManyKee workspace with:
//
//   cargo build --manifest-path rust/Cargo.toml -p keepassxc-ffi --release
//
// then copy or symlink the artifact next to your Dart executable, or set
// LD_LIBRARY_PATH / DYLD_LIBRARY_PATH / PATH accordingly.

import 'dart:io';

import 'package:keepass/keepass.dart';

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln('usage: keepass_example <vault.kdbx> <password>');
    exitCode = 64;
    return;
  }

  final db = Database.open(args[0], password: args[1]);
  try {
    _printGroup(db.rootGroup, indent: 0);
  } finally {
    db.close();
  }
}

void _printGroup(Group group, {required int indent}) {
  final pad = '  ' * indent;
  stdout.writeln('$pad[${group.name}]');

  for (final entry in group.entries) {
    final title = entry.getField('Title') ?? '(untitled)';
    final user = entry.getField('UserName') ?? '';
    stdout.writeln('$pad  - $title  $user'.trimRight());
  }

  for (final child in group.groups) {
    _printGroup(child, indent: indent + 1);
  }
}
