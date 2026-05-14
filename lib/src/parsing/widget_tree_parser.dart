import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../model/widget_node.dart';
import 'widget_visitor.dart';

/// Parses a Dart source string into a `WidgetTreeModel`.
///
/// M1 scope: finds the first `ClassDeclaration` containing a method named
/// `build` whose body returns a widget tree, then walks that return
/// expression. Imports and other top-level constructs are not modeled — see
/// Settled Decisions Q5 in DEVLOG.md.
WidgetTreeModel parseWidgetTree(String source) {
  final result = parseString(content: source, throwIfDiagnostics: false);
  final unit = result.unit;

  for (final declaration in unit.declarations) {
    if (declaration is! ClassDeclaration) {
      continue;
    }

    // Index in-class methods (other than `build`) so the visitor can
    // resolve helper-method calls (M5). All non-`build` methods are
    // included; the visitor restricts resolution to no-arg calls.
    final classMethods = <String, MethodDeclaration>{};
    MethodDeclaration? buildMethod;
    for (final member in declaration.members) {
      if (member is! MethodDeclaration) {
        continue;
      }
      if (member.name.lexeme == 'build') {
        buildMethod = member;
      } else {
        classMethods[member.name.lexeme] = member;
      }
    }
    if (buildMethod == null) {
      continue;
    }

    // Multi-reference defense: pre-scan the build body and each helper
    // body for argumentless self-target calls to in-class methods.
    // Helpers invoked from more than one call site can't be safely
    // represented as `MethodReferenceNode` — an in-memory edit through
    // one reference would diverge from the reparsed model (which sees
    // the helper-source change reflected at every call site). Such
    // helpers are removed from the lookup map, so the visitor emits
    // `OpaqueNode` for every reference.
    final referenceCounts = _countMethodReferences(
      knownMethods: classMethods.keys.toSet(),
      bodies: [buildMethod.body, ...classMethods.values.map((m) => m.body)],
    );
    final safeMethods = <String, MethodDeclaration>{
      for (final entry in classMethods.entries)
        if ((referenceCounts[entry.key] ?? 0) <= 1) entry.key: entry.value,
    };

    final root = _extractRootExpression(buildMethod);
    if (root == null) {
      throw const ParseException(
        'build() found but has no return expression',
      );
    }
    final visitor = WidgetVisitor(source, classMethods: safeMethods);
    return WidgetTreeModel(root: visitor.convertWidget(root));
  }

  throw const ParseException(
    'No build() method found in any class declaration',
  );
}

/// Walks the given AST `bodies` and returns, for each name in
/// `knownMethods`, how many times it appears as a no-target,
/// zero-argument `MethodInvocation`. Used to detect helper methods
/// that would be referenced from multiple call sites — those can't be
/// safely modeled as `MethodReferenceNode`, so the parser drops them
/// from the visitor's lookup map and they fall through to `OpaqueNode`.
Map<String, int> _countMethodReferences({
  required Set<String> knownMethods,
  required Iterable<FunctionBody> bodies,
}) {
  final visitor = _ReferenceCounter(knownMethods);
  for (final body in bodies) {
    body.accept(visitor);
  }
  return visitor.counts;
}

class _ReferenceCounter extends RecursiveAstVisitor<void> {
  _ReferenceCounter(this._knownMethods);

  final Set<String> _knownMethods;
  final Map<String, int> counts = <String, int>{};

  @override
  void visitMethodInvocation(MethodInvocation node) {
    super.visitMethodInvocation(node);
    if (node.target != null) {
      return;
    }
    if (node.argumentList.arguments.isNotEmpty) {
      return;
    }
    final name = node.methodName.name;
    if (!_knownMethods.contains(name)) {
      return;
    }
    counts.update(name, (n) => n + 1, ifAbsent: () => 1);
  }
}

Expression? _extractRootExpression(MethodDeclaration method) {
  final body = method.body;
  if (body is ExpressionFunctionBody) {
    return body.expression;
  }
  if (body is BlockFunctionBody) {
    for (final stmt in body.block.statements) {
      if (stmt is ReturnStatement) {
        return stmt.expression;
      }
    }
  }
  return null;
}
