import 'dart:io';

import 'package:loom/loom.dart';

void main(List<String> args) {
  if (args.isEmpty || args.first == '--help' || args.first == '-h') {
    _printUsage(stdout);
    return;
  }

  final command = args.first;
  final rest = args.sublist(1);

  if (command == 'parse') {
    exitCode = _runParse(rest);
    return;
  }

  stderr.writeln('loom: unknown command "$command"');
  _printUsage(stderr);
  exitCode = 1;
}

void _printUsage(IOSink sink) {
  sink
    ..writeln('loom - two-way Flutter widget kernel')
    ..writeln('')
    ..writeln('Usage:')
    ..writeln(
      '  loom parse <file>   read a Dart source file and print its widget tree',
    );
}

int _runParse(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('loom parse: missing <file> argument');
    _printUsage(stderr);
    return 1;
  }
  final path = args.first;
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('loom parse: file not found: $path');
    return 1;
  }
  final source = file.readAsStringSync();

  // Try both parsers independently — a single file commonly carries both
  // a widget tree (a `build()` method) and a route tree (a top-level
  // `final router = GoRouter(...)` or a class-field initializer). Print
  // whichever ones succeed.
  WidgetTreeModel? widgetModel;
  ParseException? widgetError;
  try {
    widgetModel = parseWidgetTree(source);
  } on ParseException catch (e) {
    widgetError = e;
  }

  RouteTreeModel? routeModel;
  ParseException? routeError;
  try {
    routeModel = parseRouteTree(source);
  } on ParseException catch (e) {
    routeError = e;
  }

  if (widgetModel == null && routeModel == null) {
    stderr.writeln('loom parse: ${widgetError!.message}');
    stderr.writeln('loom parse: ${routeError!.message}');
    return 1;
  }

  if (widgetModel != null) {
    _printTree(widgetModel, stdout);
  }
  if (routeModel != null) {
    if (widgetModel != null) {
      stdout.writeln('');
    }
    _printRouteTree(routeModel, stdout);
  }
  return 0;
}

void _printTree(WidgetTreeModel model, IOSink sink) {
  final rootDesc = switch (model.root) {
    final WidgetNode w => 'rootClass=${w.className}',
    final OpaqueNode _ => 'rootType=OpaqueNode',
    final MethodReferenceNode m =>
      'rootType=MethodReferenceNode(${m.methodName})',
    RouteNode() => throw StateError(
        'Widget tree contains a RouteNode (visitor invariant violated)',
      ),
  };
  final diagSuffix = model.diagnostics.isEmpty
      ? ''
      : ', ${model.diagnostics.length} diagnostic(s)';
  sink.writeln('WidgetTreeModel($rootDesc$diagSuffix)');
  for (final diag in model.diagnostics) {
    sink.writeln(
        '  ! ${diag.message} @${diag.span.offset}+${diag.span.length}');
  }
  _printNode(model.root, sink, '  ');
}

void _printNode(ModelNode node, IOSink sink, String indent) {
  switch (node) {
    case final WidgetNode w:
      _printWidget(w, sink, indent);
    case final OpaqueNode o:
      final preview = o.sourceText.length > 40
          ? '${o.sourceText.substring(0, 40).replaceAll('\n', '\\n')}...'
          : o.sourceText.replaceAll('\n', '\\n');
      sink.writeln(
        '$indent<opaque @${o.sourceSpan.offset}+${o.sourceSpan.length}> "$preview"',
      );
    case final MethodReferenceNode m:
      sink.writeln(
        '$indent-> ${m.methodName}()  '
        '[call @${m.callSourceSpan.offset}+${m.callSourceSpan.length}]',
      );
      _printNode(m.body, sink, '$indent    ');
    case RouteNode():
      throw StateError(
        'Widget tree contains a RouteNode (visitor invariant violated)',
      );
  }
}

void _printWidget(WidgetNode node, IOSink sink, String indent) {
  final flags = <String>[
    '@${node.sourceSpan.offset}+${node.sourceSpan.length}',
    if (node.styleHints.hasConst) 'const',
    if (node.styleHints.hasNew) 'new',
    if (node.styleHints.hasTrailingComma) 'trailingComma',
  ];
  sink.writeln('$indent${node.className}  [${flags.join(', ')}]');
  for (final entry in node.properties.entries) {
    sink.writeln('$indent    ${entry.key}: ${_formatValue(entry.value)}');
  }
  for (final slotEntry in node.childSlots.entries) {
    sink.writeln('$indent    ${slotEntry.key}:');
    for (final child in slotEntry.value) {
      _printNode(child, sink, '$indent      ');
    }
  }
}

String _formatValue(PropertyValue value) => switch (value) {
      StringLiteralValue(value: final v) => "'$v'",
      NumLiteralValue(value: final v) => '$v',
      BoolLiteralValue(value: final v) => '$v',
      NullLiteralValue() => 'null',
      EdgeInsetsAllValue(amount: final a) => 'EdgeInsets.all($a)',
      ColorValue(argbValue: final v) =>
        'Color(0x${v.toRadixString(16).padLeft(8, '0').toUpperCase()})',
      EnumReferenceValue(typeName: final t, memberName: final m) => '$t.$m',
      OpaquePropertyValue(sourceText: final t) =>
        '<opaque "${t.length > 30 ? '${t.substring(0, 30)}...' : t}">',
    };

void _printRouteTree(RouteTreeModel model, IOSink sink) {
  final rootDesc = switch (model.root) {
    final RouteNode r => 'rootClass=${r.className}',
    final OpaqueNode _ => 'rootType=OpaqueNode',
    final MethodReferenceNode m =>
      'rootType=MethodReferenceNode(${m.methodName})',
    WidgetNode() => throw StateError(
        'Route tree contains a WidgetNode (visitor invariant violated)',
      ),
  };
  final diagSuffix = model.diagnostics.isEmpty
      ? ''
      : ', ${model.diagnostics.length} diagnostic(s)';
  sink.writeln('RouteTreeModel($rootDesc$diagSuffix)');
  for (final diag in model.diagnostics) {
    sink.writeln(
        '  ! ${diag.message} @${diag.span.offset}+${diag.span.length}');
  }
  _printRouteNode(model.root, sink, '  ');
}

void _printRouteNode(ModelNode node, IOSink sink, String indent) {
  switch (node) {
    case final RouteNode r:
      _printRoute(r, sink, indent);
    case final OpaqueNode o:
      final preview = o.sourceText.length > 40
          ? '${o.sourceText.substring(0, 40).replaceAll('\n', '\\n')}...'
          : o.sourceText.replaceAll('\n', '\\n');
      sink.writeln(
        '$indent<opaque @${o.sourceSpan.offset}+${o.sourceSpan.length}> '
        '"$preview"',
      );
    case final MethodReferenceNode m:
      sink.writeln(
        '$indent-> ${m.methodName}()  '
        '[call @${m.callSourceSpan.offset}+${m.callSourceSpan.length}]',
      );
      _printRouteNode(m.body, sink, '$indent    ');
    case WidgetNode():
      throw StateError(
        'Route tree contains a WidgetNode (visitor invariant violated)',
      );
  }
}

void _printRoute(RouteNode node, IOSink sink, String indent) {
  final flags = <String>[
    '@${node.sourceSpan.offset}+${node.sourceSpan.length}',
    if (node.styleHints.hasConst) 'const',
    if (node.styleHints.hasNew) 'new',
    if (node.styleHints.hasTrailingComma) 'trailingComma',
  ];
  sink.writeln('$indent${node.className}  [${flags.join(', ')}]');
  for (final entry in node.properties.entries) {
    sink.writeln('$indent    ${entry.key}: ${_formatValue(entry.value)}');
  }
  for (final slotEntry in node.childSlots.entries) {
    sink.writeln('$indent    ${slotEntry.key}:');
    for (final child in slotEntry.value) {
      _printRouteNode(child, sink, '$indent      ');
    }
  }
}
