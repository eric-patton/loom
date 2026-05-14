import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

import '../catalog/route_catalog.dart';
import '../model/route_node.dart';
import '../model/source_span.dart';
import 'route_visitor.dart';
import 'widget_visitor.dart' show ParseException, extractMethodReturnExpression;

/// Parses a Dart source string into a `RouteTreeModel`.
///
/// Entry-point detection (in order):
///   1. Top-level variable initializer that's a constructor call to a name
///      in `RouteCatalog.rootClassNames()` — the common shape:
///      `final router = GoRouter(routes: [...]);`
///   2. Class member: field initializer (`late final GoRouter _router =
///      GoRouter(...);`) — covered in M6.0.1 after the canonical go_router
///      examples revealed this is the more common shape than (3) in real
///      code (10 of 18 example files).
///   3. Class member: method or getter whose return expression is such a
///      call — handles `GoRouter get router => GoRouter(...)` and
///      `GoRouter buildRouter() { return GoRouter(...); }`.
///
/// If no route tree is found, throws `ParseException`.
RouteTreeModel parseRouteTree(String source) {
  final result = parseString(content: source, throwIfDiagnostics: false);
  final unit = result.unit;
  final diagnostics = <ParseDiagnostic>[
    for (final error in result.errors)
      ParseDiagnostic(
        span: SourceSpan(offset: error.offset, length: error.length),
        message: error.message,
      ),
  ];

  final rootClassNames = RouteCatalog.rootClassNames();

  for (final declaration in unit.declarations) {
    if (declaration is! TopLevelVariableDeclaration) {
      continue;
    }
    for (final variable in declaration.variables.variables) {
      final initializer = variable.initializer;
      if (initializer == null) {
        continue;
      }
      if (!_isRouteRoot(initializer, rootClassNames)) {
        continue;
      }
      final visitor = RouteVisitor(source);
      return RouteTreeModel(
        root: visitor.convertRouteTreeNode(initializer),
        diagnostics: diagnostics,
      );
    }
  }

  for (final declaration in unit.declarations) {
    if (declaration is! ClassDeclaration) {
      continue;
    }

    // Two parallel candidates: a method whose return expression is a
    // route root, or a field whose initializer is one. First match wins.
    // Either way, every other in-class method gets stashed in classMethods
    // so the visitor can resolve `_homeRoute()`-style helper calls.
    final classMethods = <String, MethodDeclaration>{};
    MethodDeclaration? rootMethod;
    Expression? rootFieldInitializer;

    for (final member in declaration.body.members) {
      if (member is MethodDeclaration) {
        final returnExpr = extractMethodReturnExpression(member);
        if (returnExpr != null &&
            rootMethod == null &&
            rootFieldInitializer == null &&
            _isRouteRoot(returnExpr, rootClassNames)) {
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
              _isRouteRoot(initializer, rootClassNames)) {
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
          'Route root method has no return expression',
        );
      }
      rootExpr = methodReturn;
    } else {
      rootExpr = rootFieldInitializer!;
    }

    final visitor = RouteVisitor(source, classMethods: classMethods);
    return RouteTreeModel(
      root: visitor.convertRouteTreeNode(rootExpr),
      diagnostics: diagnostics,
    );
  }

  throw const ParseException('No route tree found in this file');
}

bool _isRouteRoot(Expression expr, Set<String> rootClassNames) {
  if (expr is InstanceCreationExpression) {
    final type = expr.constructorName.type;
    final prefixToken = type.importPrefix;
    // `prefix.GoRouter(...)` → prefix is the import alias, not the class
    // name. The class name itself is the local name, which is what
    // RouteCatalog keys on. (Matches how the visitor resolves prefixed
    // constructors: when an importPrefix is present, the local name is
    // the named constructor; we still want the catalog lookup keyed by
    // the class.)
    final name = prefixToken == null ? type.name.lexeme : type.name.lexeme;
    return rootClassNames.contains(name);
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
