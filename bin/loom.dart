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

  // Try all three parsers independently — a single file commonly carries
  // multiple tree kinds (e.g., a widget tree alongside a top-level
  // GoRouter). Print whichever ones succeed.
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

  PipelineTreeModel? pipelineModel;
  ParseException? pipelineError;
  try {
    pipelineModel = parsePipelineTree(source);
  } on ParseException catch (e) {
    pipelineError = e;
  }

  if (widgetModel == null && routeModel == null && pipelineModel == null) {
    stderr.writeln('loom parse: ${widgetError!.message}');
    stderr.writeln('loom parse: ${routeError!.message}');
    stderr.writeln('loom parse: ${pipelineError!.message}');
    return 1;
  }

  var hasPrinted = false;
  if (widgetModel != null) {
    _printTree(widgetModel, stdout);
    hasPrinted = true;
  }
  if (routeModel != null) {
    if (hasPrinted) stdout.writeln('');
    _printRouteTree(routeModel, stdout);
    hasPrinted = true;
  }
  if (pipelineModel != null) {
    if (hasPrinted) stdout.writeln('');
    _printPipelineTree(pipelineModel, stdout);
  }
  return 0;
}

void _printTree(WidgetTreeModel model, IOSink sink) {
  final rootDesc = switch (model.root) {
    final WidgetNode w => 'rootClass=${w.className}',
    final OpaqueNode _ => 'rootType=OpaqueNode',
    final MethodReferenceNode m =>
      'rootType=MethodReferenceNode(${m.methodName})',
    RouteNode() || PipelineNode() => throw StateError(
        'Widget tree contains a non-widget modeled node '
        '(visitor invariant violated)',
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
    case PipelineNode():
      throw StateError(
        'Widget tree contains a non-widget modeled node '
        '(visitor invariant violated)',
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
    WidgetNode() || PipelineNode() => throw StateError(
        'Route tree contains a non-route modeled node '
        '(visitor invariant violated)',
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
    case PipelineNode():
      throw StateError(
        'Route tree contains a non-route modeled node '
        '(visitor invariant violated)',
      );
  }
}

void _printPipelineTree(PipelineTreeModel model, IOSink sink) {
  final rootDesc = switch (model.root) {
    final PipelineNode p => 'rootClass=${p.className}',
    final OpaqueNode _ => 'rootType=OpaqueNode',
    final MethodReferenceNode m =>
      'rootType=MethodReferenceNode(${m.methodName})',
    WidgetNode() || RouteNode() => throw StateError(
        'Pipeline tree contains a non-pipeline modeled node '
        '(visitor invariant violated)',
      ),
  };
  final diagSuffix = model.diagnostics.isEmpty
      ? ''
      : ', ${model.diagnostics.length} diagnostic(s)';
  sink.writeln('PipelineTreeModel($rootDesc$diagSuffix)');
  for (final diag in model.diagnostics) {
    sink.writeln(
        '  ! ${diag.message} @${diag.span.offset}+${diag.span.length}');
  }
  _printPipelineNode(model.root, sink, '  ');
}

void _printPipelineNode(ModelNode node, IOSink sink, String indent) {
  switch (node) {
    case final PipelineNode p:
      _printPipeline(p, sink, indent);
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
      _printPipelineNode(m.body, sink, '$indent    ');
    case WidgetNode():
    case RouteNode():
      throw StateError(
        'Pipeline tree contains a non-pipeline modeled node '
        '(visitor invariant violated)',
      );
  }
}

void _printPipeline(PipelineNode node, IOSink sink, String indent) {
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
      _printPipelineNode(child, sink, '$indent      ');
    }
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
