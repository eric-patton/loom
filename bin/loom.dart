import 'dart:io';

void main(List<String> args) {
  if (args.isEmpty || args.first == '--help' || args.first == '-h') {
    stdout
      ..writeln('loom - two-way Flutter widget kernel')
      ..writeln('')
      ..writeln('Usage:')
      ..writeln(
          '  loom parse <file>   (not yet implemented; see PROJECT_SPEC.md M1)');
    return;
  }
  stderr.writeln('loom: command not yet implemented (M1 in progress).');
  exitCode = 1;
}
