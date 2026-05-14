import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/syntactic_entity.dart';
import 'package:analyzer/dart/ast/token.dart';

import '../catalog/route_catalog.dart';
import '../model/list_slot_style.dart';
import '../model/node.dart';
import '../model/property_value.dart';
import '../model/source_span.dart';
import '../model/style_hints.dart';
import 'widget_visitor.dart' show extractMethodReturnExpression;

/// Walks a route expression and produces a `ModelNode` (a `RouteNode` for
/// modeled constructor calls, otherwise `OpaqueNode` or
/// `MethodReferenceNode`).
///
/// Adapted copy of `WidgetVisitor` (M6.0 build-alongside): same scaffolding,
/// different catalog. Phase 2 of M6.1 will lift the shared scaffolding into
/// a base class; for now the duplication remains visible.
///
/// The EdgeInsets / Color special-casing on the widget side is
/// intentionally absent here — routes don't use those property shapes.
class RouteVisitor {
  RouteVisitor(
    this.source, {
    Map<String, MethodDeclaration> classMethods = const {},
  }) : _classMethods = classMethods;

  /// The full source string the model was parsed from.
  final String source;

  /// In-class helper methods (typically returning a `RouteBase`), indexed
  /// by name. Same role as on `WidgetVisitor`: enables resolution of
  /// `_homeRoute()`-style helper calls inside a `routes:` list. M6.0 does
  /// NOT enforce the widget-side multi-reference defense — top-level
  /// `parseRouteTree` rarely exercises helpers, and a route helper used
  /// twice would still re-emit verbatim from the helper's own location.
  /// Tighten this in a later milestone if real-world scout finds cases.
  final Map<String, MethodDeclaration> _classMethods;

  final Set<String> _resolvingMethods = <String>{};

  /// Converts an expression in a route-tree position to a `ModelNode`.
  /// Returns a `RouteNode` for modeled catalog constructor calls; falls
  /// through to `MethodReferenceNode` (in-class helpers) or `OpaqueNode`
  /// otherwise. Never throws.
  ModelNode convertRouteTreeNode(Expression expr) {
    if (expr is MethodInvocation &&
        expr.target == null &&
        expr.typeArguments == null &&
        expr.argumentList.arguments.isEmpty) {
      final methodName = expr.methodName.name;
      final decl = _classMethods[methodName];
      if (decl != null && !_resolvingMethods.contains(methodName)) {
        return _buildMethodReference(expr, decl);
      }
    }

    final call = _tryExtractCall(expr);
    if (call == null) {
      return _opaqueNode(expr);
    }
    if (call.namedConstructor != null) {
      return _opaqueNode(expr);
    }
    final spec = RouteCatalog.specFor(call.className);
    if (spec == null) {
      return _opaqueNode(expr);
    }
    return _buildRouteNode(call, spec);
  }

  ModelNode _buildMethodReference(
    MethodInvocation callExpr,
    MethodDeclaration declaration,
  ) {
    final bodyExpr = extractMethodReturnExpression(declaration);
    if (bodyExpr == null) {
      return _opaqueNode(callExpr);
    }
    final methodName = declaration.name.lexeme;
    _resolvingMethods.add(methodName);
    try {
      final body = convertRouteTreeNode(bodyExpr);
      return MethodReferenceNode(
        methodName: methodName,
        callSourceSpan: _span(callExpr),
        body: body,
      );
    } finally {
      _resolvingMethods.remove(methodName);
    }
  }

  OpaqueNode _opaqueNode(SyntacticEntity entity) {
    final span = _span(entity);
    return OpaqueNode(
      sourceSpan: span,
      sourceText: source.substring(span.offset, span.offset + span.length),
    );
  }

  OpaquePropertyValue _opaqueProperty(SyntacticEntity entity) {
    final span = _span(entity);
    return OpaquePropertyValue(
      span: span,
      sourceText: source.substring(span.offset, span.offset + span.length),
    );
  }

  RouteNode _buildRouteNode(_CallInfo call, RouteSpec spec) {
    final properties = <String, PropertyValue>{};
    final childSlots = <String, List<ModelNode>>{};
    final childSlotStyles = <String, ListSlotStyle>{};

    final args = call.argumentList.arguments;
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (arg is NamedArgument) {
        final name = arg.name.lexeme;
        final slotShape = spec.childSlots[name];
        if (slotShape != null) {
          final slot = _collectChildSlot(arg.argumentExpression, slotShape);
          childSlots[name] = slot.children;
          if (slot.style != null) {
            childSlotStyles[name] = slot.style!;
          }
        } else {
          properties[name] = _convertProperty(arg.argumentExpression);
        }
      } else if (arg is Expression) {
        final propName = spec.positionalToProperty[i];
        if (propName == null) {
          properties['$kPositionalOpaqueKeyPrefix$i'] = _opaqueProperty(arg);
        } else {
          properties[propName] = _convertProperty(arg);
        }
      }
    }

    return RouteNode(
      className: call.className,
      properties: properties,
      childSlots: childSlots,
      childSlotStyles: childSlotStyles,
      sourceSpan: call.span,
      styleHints: _hintsFromCall(call),
    );
  }

  ({List<ModelNode> children, ListSlotStyle? style}) _collectChildSlot(
    Expression slotExpr,
    ChildSlotShape shape,
  ) {
    if (shape == ChildSlotShape.list) {
      if (slotExpr is! ListLiteral) {
        return (
          children: <ModelNode>[_opaqueNode(slotExpr)],
          style: null,
        );
      }
      final children = <ModelNode>[];
      for (final element in slotExpr.elements) {
        if (element is Expression) {
          children.add(convertRouteTreeNode(element));
        } else {
          children.add(_opaqueNode(element));
        }
      }
      return (children: children, style: _listStyle(slotExpr));
    }
    return (
      children: <ModelNode>[convertRouteTreeNode(slotExpr)],
      style: null,
    );
  }

  ListSlotStyle _listStyle(ListLiteral list) {
    final left = list.leftBracket;
    final right = list.rightBracket;
    final span = SourceSpan(
      offset: left.offset,
      length: right.offset + right.length - left.offset,
    );
    final tokenBeforeRight = right.previous;
    final hasTrailingComma =
        tokenBeforeRight != null && tokenBeforeRight.lexeme == ',';
    final interior = source.substring(left.offset + left.length, right.offset);
    final isMultiLine = interior.contains('\n');
    return ListSlotStyle(
      bracketsSpan: span,
      hasTrailingComma: hasTrailingComma,
      isMultiLine: isMultiLine,
    );
  }

  /// Converts a route-property expression to a `PropertyValue`. Mirrors
  /// the widget side minus the EdgeInsets / Color special cases — routes
  /// don't model those shapes. Function literals (`builder:` callbacks) and
  /// anything else outside the literal set flow through `_opaqueProperty`.
  PropertyValue _convertProperty(Expression expr) {
    if (expr is SimpleStringLiteral) {
      if (expr.isRaw || expr.isMultiline) {
        return _opaqueProperty(expr);
      }
      return StringLiteralValue(
        value: expr.value,
        usesDoubleQuotes: !expr.isSingleQuoted,
        span: _span(expr),
      );
    }
    if (expr is IntegerLiteral) {
      final value = expr.value;
      if (value != null) {
        return NumLiteralValue(
          value: value,
          isDouble: false,
          span: _span(expr),
        );
      }
    }
    if (expr is DoubleLiteral) {
      return NumLiteralValue(
        value: expr.value,
        isDouble: true,
        span: _span(expr),
      );
    }
    if (expr is BooleanLiteral) {
      return BoolLiteralValue(value: expr.value, span: _span(expr));
    }
    if (expr is NullLiteral) {
      return NullLiteralValue(span: _span(expr));
    }
    if (expr is PrefixedIdentifier) {
      return EnumReferenceValue(
        typeName: expr.prefix.name,
        memberName: expr.identifier.name,
        span: _span(expr),
      );
    }
    return _opaqueProperty(expr);
  }

  StyleHints _hintsFromCall(_CallInfo call) {
    final kw = call.keyword?.keyword;
    final rightParen = call.argumentList.rightParenthesis;
    final prev = rightParen.previous;
    final hasTrailingComma = prev != null && prev.lexeme == ',';
    return StyleHints(
      hasConst: kw == Keyword.CONST,
      hasNew: kw == Keyword.NEW,
      hasTrailingComma: hasTrailingComma,
    );
  }

  SourceSpan _span(SyntacticEntity entity) =>
      SourceSpan(offset: entity.offset, length: entity.length);

  _CallInfo? _tryExtractCall(Expression expr) {
    if (expr is InstanceCreationExpression) {
      final type = expr.constructorName.type;
      final prefixToken = type.importPrefix;
      final localName = type.name.lexeme;
      final explicitNamedCtor = expr.constructorName.name?.name;

      String className;
      String? namedConstructor;
      if (prefixToken != null) {
        if (explicitNamedCtor != null) {
          return null;
        }
        className = prefixToken.name.lexeme;
        namedConstructor = localName;
      } else {
        className = localName;
        namedConstructor = explicitNamedCtor;
      }
      return _CallInfo(
        className: className,
        namedConstructor: namedConstructor,
        argumentList: expr.argumentList,
        keyword: expr.keyword,
        span: _span(expr),
      );
    }
    if (expr is MethodInvocation) {
      final target = expr.target;
      if (target == null) {
        return _CallInfo(
          className: expr.methodName.name,
          namedConstructor: null,
          argumentList: expr.argumentList,
          keyword: null,
          span: _span(expr),
        );
      }
      if (target is SimpleIdentifier) {
        return _CallInfo(
          className: target.name,
          namedConstructor: expr.methodName.name,
          argumentList: expr.argumentList,
          keyword: null,
          span: _span(expr),
        );
      }
    }
    return null;
  }
}

class _CallInfo {
  _CallInfo({
    required this.className,
    required this.namedConstructor,
    required this.argumentList,
    required this.keyword,
    required this.span,
  });

  final String className;
  final String? namedConstructor;
  final ArgumentList argumentList;
  final Token? keyword;
  final SourceSpan span;
}
