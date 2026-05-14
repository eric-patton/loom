// ignore_for_file: dangling_library_doc_comments

/// Scout: run `parseWidgetTree` + no-op idempotence over every `.dart`
/// file in a directory tree. Used to stress-test the kernel against real-
/// world code beyond the pinned fixture corpus.
///
/// Tracks four outcomes per file:
///   - parsed clean: model built, zero analyzer diagnostics
///   - parsed with diagnostics: model built, but the analyzer
///     error-recovered (Q4 surface)
///   - ParseException: expected for non-widget files (no `build()` etc.)
///   - other exception: a kernel crash on shape we don't handle gracefully
///
/// And the invariant we ALWAYS check on parsed files:
///   - `applySourceEdits(source, []) == source`
///
/// Exit 0 if zero crashes and zero idempotence failures; 1 otherwise.
import 'dart:io';

import 'package:loom/loom.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart tool/scout.dart <dir>');
    exitCode = 1;
    return;
  }
  final root = Directory(args.first);
  if (!root.existsSync()) {
    stderr.writeln('not a directory: ${args.first}');
    exitCode = 1;
    return;
  }

  var total = 0;
  var parsedClean = 0;
  var parsedWithDiagnostics = 0;
  var threwParseException = 0;
  var threwOther = 0;
  var idempotenceFailed = 0;
  final crashes = <_Crash>[];
  final idempotenceFails = <String>[];
  final diagnosticFiles = <String>[];
  final cleanSamples = <String>[];

  for (final entity in root.listSync(recursive: true)) {
    if (entity is! File) {
      continue;
    }
    if (!entity.path.endsWith('.dart')) {
      continue;
    }
    total++;

    final String source;
    try {
      source = entity.readAsStringSync();
    } catch (_) {
      continue;
    }

    try {
      final model = parseWidgetTree(source);
      if (model.diagnostics.isEmpty) {
        parsedClean++;
        if (cleanSamples.length < 5) {
          final rootDesc = switch (model.root) {
            final WidgetNode w => 'WidgetNode(${w.className})',
            final MethodReferenceNode m =>
              'MethodReferenceNode(${m.methodName})',
            OpaqueNode _ => 'OpaqueNode',
          };
          cleanSamples.add('${entity.path} -> $rootDesc');
        }
      } else {
        parsedWithDiagnostics++;
        diagnosticFiles.add('${entity.path} (${model.diagnostics.length})');
      }
      final result = applySourceEdits(source, const <SourceEdit>[]);
      if (result != source) {
        idempotenceFailed++;
        idempotenceFails.add(entity.path);
      }
    } on ParseException {
      threwParseException++;
    } on Object catch (e, st) {
      threwOther++;
      crashes.add(_Crash(entity.path, e, st));
    }
  }

  stdout.writeln('Scout summary for ${root.path}:');
  stdout.writeln('  Total .dart files:                $total');
  stdout.writeln('  Parsed clean:                     $parsedClean');
  stdout.writeln('  Parsed with diagnostics:          $parsedWithDiagnostics');
  stdout.writeln('  ParseException (non-widget file): $threwParseException');
  stdout.writeln('  Other exception (CRASH):          $threwOther');
  stdout.writeln('  Idempotence failed:               $idempotenceFailed');

  if (crashes.isNotEmpty) {
    stdout.writeln('');
    stdout.writeln('Crashes:');
    for (final crash in crashes) {
      stdout.writeln('  ${crash.path}');
      stdout.writeln('    ${crash.error.runtimeType}: ${crash.error}');
      final lines = crash.stack.toString().split('\n');
      for (final line in lines.take(8)) {
        if (line.trim().isNotEmpty) {
          stdout.writeln('    $line');
        }
      }
      stdout.writeln('');
    }
  }
  if (idempotenceFails.isNotEmpty) {
    stdout.writeln('');
    stdout.writeln('Idempotence failures:');
    for (final path in idempotenceFails) {
      stdout.writeln('  $path');
    }
  }
  if (diagnosticFiles.isNotEmpty) {
    stdout.writeln('');
    stdout.writeln('Files with analyzer diagnostics:');
    for (final entry in diagnosticFiles) {
      stdout.writeln('  $entry');
    }
  }
  if (cleanSamples.isNotEmpty) {
    stdout.writeln('');
    stdout.writeln('Clean-parse samples (first 5):');
    for (final entry in cleanSamples) {
      stdout.writeln('  $entry');
    }
  }

  exitCode = (crashes.isEmpty && idempotenceFailed == 0) ? 0 : 1;
}

class _Crash {
  _Crash(this.path, this.error, this.stack);
  final String path;
  final Object error;
  final StackTrace stack;
}
