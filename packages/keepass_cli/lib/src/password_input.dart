import 'dart:io';

String promptPassword(String label) {
  if (!stdin.hasTerminal) {
    stderr.writeln(
      'Error: no password supplied and stdin is not a terminal; '
      'pass --password or set KEEPASS_PASSWORD.',
    );
    exit(64);
  }
  stdout.write('$label: ');
  stdin.echoMode = false;
  try {
    final password = stdin.readLineSync() ?? '';
    stdout.writeln(); // newline after hidden input
    return password;
  } finally {
    stdin.echoMode = true;
  }
}

String getPassword({
  required String? flag,
  required String envVar,
  required String promptLabel,
}) {
  if (flag != null && flag.isNotEmpty) return flag;
  final env = Platform.environment[envVar];
  if (env != null && env.isNotEmpty) return env;
  return promptPassword(promptLabel);
}
