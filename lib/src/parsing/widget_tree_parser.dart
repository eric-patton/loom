import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

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
    for (final member in declaration.members) {
      if (member is! MethodDeclaration) {
        continue;
      }
      if (member.name.lexeme == 'build') {
        continue;
      }
      classMethods[member.name.lexeme] = member;
    }

    for (final member in declaration.members) {
      if (member is! MethodDeclaration) {
        continue;
      }
      if (member.name.lexeme != 'build') {
        continue;
      }
      final root = _extractRootExpression(member);
      if (root == null) {
        throw const ParseException(
          'build() found but has no return expression',
        );
      }
      final visitor = WidgetVisitor(source, classMethods: classMethods);
      return WidgetTreeModel(root: visitor.convertWidget(root));
    }
  }

  throw const ParseException(
    'No build() method found in any class declaration',
  );
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
