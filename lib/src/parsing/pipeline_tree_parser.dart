import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

import '../catalog/pipeline_catalog.dart';
import '../model/node.dart';
import '../model/source_span.dart';
import 'base_visitor.dart';
import 'pipeline_visitor.dart';

/// Parses a Dart source string into a `PipelineTreeModel`.
///
/// Entry-point detection (same shape as `parseRouteTree`):
///   1. Top-level variable initializer that's a `Pipeline(...)` call —
///      the canonical shape: `final pipeline = Pipeline(steps: [...]);`
///   2. Class member: field initializer or method-return whose value is
///      such a call.
///
/// If no pipeline tree is found, throws `ParseException`.
PipelineTreeModel parsePipelineTree(String source) {
  final result = parseString(content: source, throwIfDiagnostics: false);
  final unit = result.unit;
  final diagnostics = <ParseDiagnostic>[
    for (final error in result.errors)
      ParseDiagnostic(
        span: SourceSpan(offset: error.offset, length: error.length),
        message: error.message,
      ),
  ];

  final rootClassNames = PipelineCatalog.rootClassNames();

  for (final declaration in unit.declarations) {
    if (declaration is! TopLevelVariableDeclaration) {
      continue;
    }
    for (final variable in declaration.variables.variables) {
      final initializer = variable.initializer;
      if (initializer == null) {
        continue;
      }
      if (!_isPipelineRoot(initializer, rootClassNames)) {
        continue;
      }
      final visitor = PipelineVisitor(source);
      return PipelineTreeModel(
        root: visitor.convertNode(initializer),
        diagnostics: diagnostics,
      );
    }
  }

  for (final declaration in unit.declarations) {
    if (declaration is! ClassDeclaration) {
      continue;
    }

    final classMethods = <String, MethodDeclaration>{};
    MethodDeclaration? rootMethod;
    Expression? rootFieldInitializer;

    for (final member in declaration.body.members) {
      if (member is MethodDeclaration) {
        final returnExpr = extractMethodReturnExpression(member);
        if (returnExpr != null &&
            rootMethod == null &&
            rootFieldInitializer == null &&
            _isPipelineRoot(returnExpr, rootClassNames)) {
          rootMethod = member;
        } else {
          classMethods[member.name.lexeme] = member;
        }
      } else if (member is FieldDeclaration &&
          rootMethod == null &&
          rootFieldInitializer == null) {
        for (final variable in member.fields.variables) {
          final initializer = variable.initializer;
          if (initializer != null &&
              _isPipelineRoot(initializer, rootClassNames)) {
            rootFieldInitializer = initializer;
            break;
          }
        }
      }
    }

    if (rootMethod == null && rootFieldInitializer == null) {
      continue;
    }

    final Expression rootExpr;
    if (rootMethod != null) {
      final methodReturn = extractMethodReturnExpression(rootMethod);
      if (methodReturn == null) {
        throw const ParseException(
          'Pipeline root method has no return expression',
        );
      }
      rootExpr = methodReturn;
    } else {
      rootExpr = rootFieldInitializer!;
    }

    final visitor = PipelineVisitor(source, classMethods: classMethods);
    return PipelineTreeModel(
      root: visitor.convertNode(rootExpr),
      diagnostics: diagnostics,
    );
  }

  throw const ParseException('No pipeline tree found in this file');
}

bool _isPipelineRoot(Expression expr, Set<String> rootClassNames) {
  if (expr is InstanceCreationExpression) {
    return rootClassNames.contains(expr.constructorName.type.name.lexeme);
  }
  if (expr is MethodInvocation) {
    final target = expr.target;
    if (target == null) {
      return rootClassNames.contains(expr.methodName.name);
    }
    if (target is SimpleIdentifier) {
      return rootClassNames.contains(target.name);
    }
  }
  return false;
}
