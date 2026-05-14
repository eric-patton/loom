import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/syntactic_entity.dart';
import 'package:analyzer/dart/ast/token.dart';

import '../catalog/widget_catalog.dart';
import '../model/list_slot_style.dart';
import '../model/property_value.dart';
import '../model/source_span.dart';
import '../model/style_hints.dart';
import '../model/widget_node.dart';

/// Thrown when the visitor cannot produce a `WidgetNode` at the root of
/// the parse — typically because the build method returns an expression
/// the kernel doesn't recognize as a widget constructor (e.g.
/// `Widget build() => _build();` where `_build` is opaque).
///
/// Once M4 opacity is in, the visitor no longer throws on internal
/// unmodelable expressions — it emits `OpaqueNode` or `OpaquePropertyValue`
/// instead. `ParseException` is reserved for the rare case where the
/// model's root would itself be opaque.
class ParseException implements Exception {
  const ParseException(this.message, [this.span]);

  final String message;
  final SourceSpan? span;

  @override
  String toString() =>
      'ParseException: $message${span == null ? '' : ' at $span'}';
}

class WidgetVisitor {
  WidgetVisitor(
    this.source, {
    Map<String, MethodDeclaration> classMethods = const {},
  }) : _classMethods = classMethods;

  /// The full source string the model was parsed from. Used at parse time
  /// to detect list-literal multi-line shape and to anchor opaque-node
  /// source ranges.
  final String source;

  /// In-class helper methods that return a Widget, indexed by name.
  /// Used by M5 helper-method resolution. The parser populates this map
  /// from the enclosing `ClassDeclaration` before calling the visitor.
  final Map<String, MethodDeclaration> _classMethods;

  /// Methods currently being resolved (depth-first). Used to break
  /// cycles — if a recursive call would re-enter a method already on
  /// this set, we fall back to `OpaqueNode` for the inner reference
  /// instead of recursing infinitely.
  final Set<String> _resolvingMethods = <String>{};

  /// Converts an expression in a child-slot position to a `ModelNode`.
  /// Returns a `WidgetNode` if the expression is a recognized widget
  /// constructor with modelable arguments, otherwise an `OpaqueNode`
  /// pointing at the source range of the original expression. Never
  /// throws.
  ModelNode convertModelNode(Expression expr) {
    // M5: in-class helper-method reference takes priority over the
    // generic "treat any zero-arg `Foo()` as a constructor call" reading.
    // A no-target, no-arg `_methodName()` that matches an in-class method
    // resolves to a `MethodReferenceNode` (unless we'd recurse into the
    // same method, in which case it falls through to opaque).
    if (expr is MethodInvocation &&
        expr.target == null &&
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
    final spec = WidgetCatalog.specFor(call.className);
    if (spec == null) {
      return _opaqueNode(expr);
    }
    return _buildWidgetNode(call, spec);
  }

  ModelNode _buildMethodReference(
    MethodInvocation callExpr,
    MethodDeclaration declaration,
  ) {
    final bodyExpr = _extractReturnExpression(declaration);
    if (bodyExpr == null) {
      // Helper has no return expression we can model; degrade to opaque
      // at the call site.
      return _opaqueNode(callExpr);
    }
    final methodName = declaration.name.lexeme;
    _resolvingMethods.add(methodName);
    try {
      final body = convertModelNode(bodyExpr);
      return MethodReferenceNode(
        methodName: methodName,
        callSourceSpan: _span(callExpr),
        body: body,
      );
    } finally {
      _resolvingMethods.remove(methodName);
    }
  }

  Expression? _extractReturnExpression(MethodDeclaration method) {
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

  /// Converts an expression to a `WidgetNode`, throwing `ParseException`
  /// if the expression cannot be modeled as a widget at all. Used by the
  /// parser for the root of the build method's return expression — the
  /// root can't be opaque if the kernel is to do anything useful with the
  /// model.
  WidgetNode convertWidget(Expression expr) {
    final node = convertModelNode(expr);
    if (node is WidgetNode) {
      return node;
    }
    throw ParseException(
      'Root expression is opaque; the model has no editable widget tree.',
      node.sourceSpan,
    );
  }

  WidgetNode _buildWidgetNode(_CallInfo call, WidgetSpec spec) {
    final properties = <String, PropertyValue>{};
    final childSlots = <String, List<ModelNode>>{};
    final childSlotStyles = <String, ListSlotStyle>{};

    final args = call.argumentList.arguments;
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (arg is NamedExpression) {
        final name = arg.name.label.name;
        final slotShape = spec.childSlots[name];
        if (slotShape != null) {
          final slot = _collectChildSlot(arg.expression, slotShape);
          childSlots[name] = slot.children;
          if (slot.style != null) {
            childSlotStyles[name] = slot.style!;
          }
        } else {
          properties[name] = _convertProperty(arg.expression);
        }
      } else {
        final propName = spec.positionalToProperty[i];
        if (propName == null) {
          // Unmodeled positional argument: capture as an opaque property
          // under a synthetic key built from `kPositionalOpaqueKeyPrefix`
          // plus the source index. The serializer recognizes this prefix
          // and re-emits the value as a positional argument at the same
          // index, interleaved with any catalog-modeled positionals.
          properties['$kPositionalOpaqueKeyPrefix$i'] = _opaqueProperty(arg);
        } else {
          properties[propName] = _convertProperty(arg);
        }
      }
    }

    return WidgetNode(
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
        // Non-list expression in a list-shaped slot (e.g. a spread or
        // a method call returning List<Widget>). Wrap the whole thing
        // as a single opaque entry, and crucially do NOT synthesize a
        // ListSlotStyle: there is no real bracketed list literal here,
        // so structural edits must not target this slot. The visitor's
        // caller skips style assignment when style is null.
        return (
          children: <ModelNode>[_opaqueNode(slotExpr)],
          style: null,
        );
      }
      final children = <ModelNode>[];
      for (final element in slotExpr.elements) {
        if (element is Expression) {
          children.add(convertModelNode(element));
        } else {
          // Spread or if/for collection element: opaque.
          children.add(_opaqueNode(element));
        }
      }
      return (children: children, style: _listStyle(slotExpr));
    }
    return (children: <ModelNode>[convertModelNode(slotExpr)], style: null);
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

  /// Converts an expression at a property position to a `PropertyValue`.
  /// Anything outside the supported M1 literal set becomes an
  /// `OpaquePropertyValue` (M4). Total: never throws.
  PropertyValue _convertProperty(Expression expr) {
    if (expr is SimpleStringLiteral) {
      // Raw (`r'...'`) and triple-quoted (`'''...'''`) strings have
      // surface forms the kernel doesn't model; route them to opaque so
      // their bytes survive verbatim.
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
    final call = _tryExtractCall(expr);
    if (call != null) {
      final converted = _convertConstructorPropertyValue(call);
      if (converted != null) {
        return converted;
      }
    }
    // Anything else: opaque.
    return _opaqueProperty(expr);
  }

  PropertyValue? _convertConstructorPropertyValue(_CallInfo call) {
    if (call.className == 'EdgeInsets' && call.namedConstructor == 'all') {
      return _edgeInsetsAll(call);
    }
    if (call.className == 'Color' && call.namedConstructor == null) {
      return _colorLiteral(call);
    }
    return null;
  }

  PropertyValue? _edgeInsetsAll(_CallInfo call) {
    final args = call.argumentList.arguments;
    if (args.length != 1) {
      return null;
    }
    final arg = args.first;
    if (arg is IntegerLiteral) {
      final value = arg.value;
      if (value == null) {
        return null;
      }
      return EdgeInsetsAllValue(
        amount: value,
        amountIsDouble: false,
        span: call.span,
      );
    }
    if (arg is DoubleLiteral) {
      return EdgeInsetsAllValue(
        amount: arg.value,
        amountIsDouble: true,
        span: call.span,
      );
    }
    return null;
  }

  PropertyValue? _colorLiteral(_CallInfo call) {
    final args = call.argumentList.arguments;
    if (args.length != 1) {
      return null;
    }
    final arg = args.first;
    if (arg is! IntegerLiteral) {
      return null;
    }
    final value = arg.value;
    if (value == null) {
      return null;
    }
    return ColorValue(argbValue: value, span: call.span);
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

  /// Normalizes the two AST shapes a constructor-call-without-resolution can
  /// take: `InstanceCreationExpression` when `const`/`new` is present, else
  /// `MethodInvocation`. Returns null for anything else.
  ///
  /// `const Prefix.Name(...)` is a special case: the analyzer parses it as
  /// `InstanceCreationExpression` with the named-type's `importPrefix`
  /// holding `Prefix` (because syntactically that COULD be an import
  /// prefix; without resolution the analyzer can't tell). We treat this
  /// as `Prefix`-class with named constructor `Name` — the common Flutter
  /// pattern (`const EdgeInsets.all(8)`, `const Color(0x…)` with a prefix,
  /// etc.). This matches the non-const `MethodInvocation` interpretation.
  _CallInfo? _tryExtractCall(Expression expr) {
    if (expr is InstanceCreationExpression) {
      final type = expr.constructorName.type;
      final prefixToken = type.importPrefix;
      final localName = type.name2.lexeme;
      final explicitNamedCtor = expr.constructorName.name?.name;

      String className;
      String? namedConstructor;
      if (prefixToken != null) {
        // `const Prefix.X(...)`: rare to also have an explicit named ctor.
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
