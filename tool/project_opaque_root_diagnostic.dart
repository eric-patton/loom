// ignore_for_file: dangling_library_doc_comments

/// Project-aware version of `opaque_root_diagnostic.dart` — measures how
/// many root-level opaque cases the cross-file `ProjectWidgetIndex`
/// resolves.
///
/// Usage: dart tool/project_opaque_root_diagnostic.dart `<project-lib-dir>`
///
/// Walks the directory tree, builds a `ProjectModel` from every .dart
/// file found, builds a `ProjectWidgetIndex`, then parses each file
/// twice — once without the index (baseline) and once with it — and
/// reports the delta in modeled-root vs Cat C counts.
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:loom/loom.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart tool/project_opaque_root_diagnostic.dart '
        '<project-lib-dir>');
    exitCode = 1;
    return;
  }
  final root = Directory(args.first);
  if (!root.existsSync()) {
    stderr.writeln('not a directory: ${args.first}');
    exitCode = 1;
    return;
  }

  final sources = <String, String>{};
  final rootPath = root.path.replaceAll('\\', '/');
  for (final entity in root.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    try {
      // Key files by their path relative to [root], normalized to forward
      // slashes. This avoids Windows-drive-letter parsing problems
      // (`C:/...` would try to use `C` as a URI scheme). Relative paths
      // resolve cleanly through `Uri.resolveUri`.
      var path = entity.path.replaceAll('\\', '/');
      if (path.startsWith('$rootPath/')) {
        path = path.substring(rootPath.length + 1);
      }
      sources[path] = entity.readAsStringSync();
    } catch (_) {}
  }
  if (sources.isEmpty) {
    stderr.writeln('no .dart files found under ${root.path}');
    exitCode = 1;
    return;
  }

  stdout.writeln('Building ProjectModel from ${sources.length} files...');
  final project = ProjectModel.fromSources(sources);
  stdout.writeln('Building ProjectWidgetIndex...');
  final index = ProjectWidgetIndex.build(project);

  var baselineModeled = 0;
  var baselineOpaqueC = 0;
  var withIndexModeled = 0;
  var withIndexOpaqueC = 0;
  final newlyResolved = <String, int>{};

  for (final entry in sources.entries) {
    final filePath = entry.key;
    final source = entry.value;

    // Skip files without a build() method — they can't produce a widget root.
    final unit = parseString(content: source).unit;
    if (!_hasBuildMethod(unit)) continue;

    final baseline = _tryParse(source, projectWidgets: const {});
    final withIndex =
        _tryParse(source, projectWidgets: index.widgetsVisibleFrom(filePath));
    if (baseline == null || withIndex == null) continue;

    final baselineIsModeled =
        baseline.root is WidgetNode || baseline.root is MethodReferenceNode;
    final withIndexIsModeled =
        withIndex.root is WidgetNode || withIndex.root is MethodReferenceNode;

    if (baselineIsModeled) baselineModeled++;
    if (withIndexIsModeled) withIndexModeled++;

    // Cat C: opaque root that's a constructor-call to an unknown class.
    if (baseline.root is OpaqueNode) {
      final returnExpr = _findFirstBuildReturn(unit);
      if (returnExpr != null && _isUnknownClassCall(returnExpr)) {
        baselineOpaqueC++;
        final cls = _classNameOf(returnExpr);
        if (withIndexIsModeled && cls != null) {
          newlyResolved.update(cls, (n) => n + 1, ifAbsent: () => 1);
        }
      }
    }
    if (withIndex.root is OpaqueNode) {
      final returnExpr = _findFirstBuildReturn(unit);
      if (returnExpr != null && _isUnknownClassCall(returnExpr)) {
        withIndexOpaqueC++;
      }
    }
  }

  stdout.writeln('');
  stdout.writeln('Project-aware opaque-root diagnostic for ${root.path}:');
  stdout.writeln('  Files in project:            ${sources.length}');
  stdout.writeln('  Baseline modeled-root:       $baselineModeled');
  stdout.writeln('  With-index modeled-root:     $withIndexModeled');
  stdout.writeln('  Baseline Cat C (unknown):    $baselineOpaqueC');
  stdout.writeln('  With-index Cat C:            $withIndexOpaqueC');
  stdout.writeln('  Newly resolved (delta):      '
      '${withIndexModeled - baselineModeled}');
  if (newlyResolved.isNotEmpty) {
    stdout.writeln('');
    stdout.writeln('Classes resolved by cross-file index:');
    final sorted = newlyResolved.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final entry in sorted.take(20)) {
      stdout.writeln('    ${entry.value.toString().padLeft(4)}  ${entry.key}');
    }
  }
}

bool _hasBuildMethod(CompilationUnit unit) {
  for (final decl in unit.declarations) {
    if (decl is! ClassDeclaration) continue;
    for (final member in decl.body.members) {
      if (member is MethodDeclaration && member.name.lexeme == 'build') {
        return true;
      }
    }
  }
  return false;
}

Expression? _findFirstBuildReturn(CompilationUnit unit) {
  for (final decl in unit.declarations) {
    if (decl is! ClassDeclaration) continue;
    for (final member in decl.body.members) {
      if (member is! MethodDeclaration) continue;
      if (member.name.lexeme != 'build') continue;
      final body = member.body;
      if (body is ExpressionFunctionBody) return body.expression;
      if (body is BlockFunctionBody) {
        for (final stmt in body.block.statements) {
          if (stmt is ReturnStatement) return stmt.expression;
        }
      }
      return null;
    }
  }
  return null;
}

bool _isUnknownClassCall(Expression expr) {
  if (expr is InstanceCreationExpression) return true;
  if (expr is MethodInvocation) {
    final target = expr.target;
    if (target == null) return true;
    if (target is SimpleIdentifier) return true;
  }
  return false;
}

String? _classNameOf(Expression expr) {
  if (expr is InstanceCreationExpression) {
    final type = expr.constructorName.type;
    return type.importPrefix?.name.lexeme ?? type.name.lexeme;
  }
  if (expr is MethodInvocation) {
    final target = expr.target;
    if (target == null) return expr.methodName.name;
    if (target is SimpleIdentifier) return target.name;
  }
  return null;
}

WidgetTreeModel? _tryParse(
  String source, {
  required Map<String, WidgetSpec> projectWidgets,
}) {
  try {
    return parseWidgetTree(source, projectWidgets: projectWidgets);
  } on Exception {
    return null;
  }
}
