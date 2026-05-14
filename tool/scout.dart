// ignore_for_file: dangling_library_doc_comments

/// Scout: run both `parseWidgetTree` and `parseRouteTree` + no-op
/// idempotence over every `.dart` file in a directory tree. Used to
/// stress-test the kernel against real-world code beyond the pinned
/// fixture corpus.
///
/// Per-file outcomes tracked:
///   - parsed widget clean / with diagnostics
///   - parsed route clean / with diagnostics
///   - no tree found (both parsers threw `ParseException`)
///   - other exception (a kernel crash on shape we don't handle gracefully)
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
  var parsedWidgetClean = 0;
  var parsedWidgetDiagnostics = 0;
  var parsedRouteClean = 0;
  var parsedRouteDiagnostics = 0;
  var noTreeFound = 0;
  var threwOther = 0;
  var idempotenceFailed = 0;
  final crashes = <_Crash>[];
  final idempotenceFails = <String>[];
  final diagnosticFiles = <String>[];
  final widgetSamples = <String>[];
  final routeSamples = <String>[];

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

    // Try both parsers independently — a single file commonly has both
    // a build() method (widget tree) AND a top-level GoRouter declaration
    // (route tree). Counting them separately lets the scout reflect what
    // the file actually contains rather than picking one and masking the
    // other.
    var widgetParsed = false;
    var routeParsed = false;
    var crashed = false;

    try {
      final widgetModel = parseWidgetTree(source);
      widgetParsed = true;
      if (widgetModel.diagnostics.isEmpty) {
        parsedWidgetClean++;
        if (widgetSamples.length < 5) {
          final rootDesc = switch (widgetModel.root) {
            final WidgetNode w => 'WidgetNode(${w.className})',
            final MethodReferenceNode m =>
              'MethodReferenceNode(${m.methodName})',
            OpaqueNode _ => 'OpaqueNode',
            final RouteNode r => 'RouteNode(${r.className})',
          };
          widgetSamples.add('${entity.path} -> $rootDesc');
        }
      } else {
        parsedWidgetDiagnostics++;
        diagnosticFiles
            .add('${entity.path} [widget] (${widgetModel.diagnostics.length})');
      }
    } on ParseException {
      // No widget tree here. Continue to route attempt.
    } on Object catch (e, st) {
      threwOther++;
      crashes.add(_Crash(entity.path, e, st));
      crashed = true;
    }

    if (!crashed) {
      try {
        final routeModel = parseRouteTree(source);
        routeParsed = true;
        if (routeModel.diagnostics.isEmpty) {
          parsedRouteClean++;
          if (routeSamples.length < 5) {
            final rootDesc = switch (routeModel.root) {
              final RouteNode r => 'RouteNode(${r.className})',
              final MethodReferenceNode m =>
                'MethodReferenceNode(${m.methodName})',
              OpaqueNode _ => 'OpaqueNode',
              final WidgetNode w => 'WidgetNode(${w.className})',
            };
            routeSamples.add('${entity.path} -> $rootDesc');
          }
        } else {
          parsedRouteDiagnostics++;
          diagnosticFiles
              .add('${entity.path} [route] (${routeModel.diagnostics.length})');
        }
      } on ParseException {
        // No route tree here either.
      } on Object catch (e, st) {
        threwOther++;
        crashes.add(_Crash(entity.path, e, st));
        crashed = true;
      }
    }

    if (!crashed && !widgetParsed && !routeParsed) {
      noTreeFound++;
    }

    if (widgetParsed || routeParsed) {
      final result = applySourceEdits(source, const <SourceEdit>[]);
      if (result != source) {
        idempotenceFailed++;
        idempotenceFails.add(entity.path);
      }
    }
  }

  stdout.writeln('Scout summary for ${root.path}:');
  stdout.writeln('  Total .dart files:                $total');
  stdout.writeln('  Parsed widget clean:              $parsedWidgetClean');
  stdout
      .writeln('  Parsed widget with diagnostics:   $parsedWidgetDiagnostics');
  stdout.writeln('  Parsed route clean:               $parsedRouteClean');
  stdout.writeln('  Parsed route with diagnostics:    $parsedRouteDiagnostics');
  stdout.writeln('  No tree found:                    $noTreeFound');
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
  if (widgetSamples.isNotEmpty) {
    stdout.writeln('');
    stdout.writeln('Widget clean-parse samples (first 5):');
    for (final entry in widgetSamples) {
      stdout.writeln('  $entry');
    }
  }
  if (routeSamples.isNotEmpty) {
    stdout.writeln('');
    stdout.writeln('Route clean-parse samples (first 5):');
    for (final entry in routeSamples) {
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
