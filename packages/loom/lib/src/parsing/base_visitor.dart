import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/syntactic_entity.dart';
import 'package:analyzer/dart/ast/token.dart';

import '../catalog/catalog_spec.dart';
import '../model/list_slot_style.dart';
import '../model/node.dart';
import '../model/property_value.dart';
import '../model/source_span.dart';
import '../model/style_hints.dart';

/// Thrown when the parser cannot produce a model from the source — typically
/// because no recognizable tree root was found (no `build()` method, no
/// top-level route declaration, etc.).
///
/// Once M4 opacity landed, the visitor no longer throws on internal
/// unmodelable expressions — it emits `OpaqueNode` or `OpaquePropertyValue`
/// instead. `ParseException` is reserved for the rare case where the
/// model's root itself would have to be opaque, OR for the parser
/// recognizing no tree shape at all.
class ParseException implements Exception {
  const ParseException(this.message, [this.span]);

  final String message;
  final SourceSpan? span;

  @override
  String toString() =>
      'ParseException: $message${span == null ? '' : ' at $span'}';
}

/// Information about a constructor-call-shaped expression, normalized
/// across the two AST forms it can take: `InstanceCreationExpression`
/// (when `const`/`new` is present or the constructor resolves) and
/// `MethodInvocation` (when neither). Shared between visitors.
///
/// `const Prefix.Name(...)` is a special case: the analyzer parses it as
/// `InstanceCreationExpression` with the named-type's `importPrefix`
/// holding `Prefix` (because syntactically that COULD be an import
/// prefix; without resolution the analyzer can't tell). We treat this as
/// `Prefix`-class with named constructor `Name` — matching the non-const
/// `MethodInvocation` interpretation.
class CallInfo {
  CallInfo({
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

/// Returns the `Expression` a `MethodDeclaration` returns, or `null` if
/// its body has no return expression we can model.
///
/// Handles both arrow bodies (`=> expr`) and block bodies (the first
/// top-level `ReturnStatement` wins; early returns inside `if`/`for`
/// blocks are nested and thus ignored).
Expression? extractMethodReturnExpression(MethodDeclaration method) {
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

/// Language-general visitor scaffold. Walks an expression and produces a
/// `ModelNode` (a domain-modeled node when the catalog recognizes the call,
/// otherwise `OpaqueNode` / `MethodReferenceNode`).
///
/// Subclasses provide three domain hooks:
///   * `specFor(className)` — consult the domain catalog
///   * `buildModeledNode(...)` — instantiate the concrete `ModelNode`
///     subclass (e.g. `WidgetNode` or `RouteNode`)
///   * `customConstructorPropertyValue(call)` — opt-in custom property-
///     value handling (e.g. widget-side `EdgeInsets.all(N)` / `Color(0x…)`)
///
/// M6.1 Phase 2 extracted this from the duplicated widget-side and
/// route-side visitors. Everything below this comment is genuinely
/// language-general; if you need to add behavior here that's specific to
/// widgets or routes, you're probably missing a domain hook.
abstract class BaseVisitor {
  BaseVisitor(
    this.source, {
    Map<String, MethodDeclaration> classMethods = const {},
  }) : _classMethods = classMethods;

  /// The full source string the model was parsed from. Used at parse time
  /// to detect list-literal multi-line shape and to anchor opaque-node
  /// source ranges.
  final String source;

  /// In-class helper methods (typically returning a domain-modeled type),
  /// indexed by name. Used by `MethodReferenceNode` resolution.
  final Map<String, MethodDeclaration> _classMethods;

  /// Methods currently being resolved (depth-first). Used to break cycles —
  /// if a recursive call would re-enter a method already on this set, we
  /// fall back to `OpaqueNode` for the inner reference instead of
  /// recursing infinitely.
  final Set<String> _resolvingMethods = <String>{};

  // ---------------- Domain hooks (subclass overrides) ----------------

  /// Looks up `className` in the domain catalog. Return null for unknown
  /// classes; the visitor will produce `OpaqueNode` for them.
  CatalogSpec? specFor(String className);

  /// Instantiates the concrete `ModelNode` subclass for a modeled
  /// constructor call. Subclasses construct `WidgetNode`, `RouteNode`,
  /// etc. with the collected properties + childSlots.
  ///
  /// [namedConstructor] is non-null when the call was `Class.named(...)` —
  /// the subclass must preserve it on the produced node so emission can
  /// re-render the named-ctor form.
  ModelNode buildModeledNode({
    required String className,
    required String? namedConstructor,
    required Map<String, PropertyValue> properties,
    required Map<String, List<ModelNode>> childSlots,
    required Map<String, ListSlotStyle> childSlotStyles,
    required SourceSpan sourceSpan,
    required StyleHints styleHints,
  });

  /// Opt-in hook for domain-specific `PropertyValue` recognition beyond
  /// the standard literal set (strings, numbers, booleans, null,
  /// enum-references). The widget visitor uses this for `EdgeInsets.all(N)`
  /// and `Color(0x…)`. Return null to defer to the standard opaque path.
  PropertyValue? customConstructorPropertyValue(CallInfo call) => null;

  // ---------------- Shared scaffolding ----------------

  /// Converts an expression in a tree position to a `ModelNode`.
  /// Returns a modeled node (built via `buildModeledNode`) when the
  /// catalog recognizes the call, a `MethodReferenceNode` when the
  /// expression is a recognized in-class helper-method call, or an
  /// `OpaqueNode` otherwise. Never throws.
  ModelNode convertNode(Expression expr) {
    // In-class helper-method reference takes priority over the generic
    // "treat any zero-arg `Foo()` as a constructor call" reading. A
    // no-target, no-arg, no-type-args `_methodName()` that matches an
    // in-class method resolves to a `MethodReferenceNode` (unless we'd
    // recurse into the same method, in which case it falls through to
    // opaque). Type-argumented calls (`_h<int>()`) also fall through —
    // the serializer would otherwise drop the type args on re-emission,
    // breaking the round-trip.
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

    final call = tryExtractCall(expr);
    if (call == null) {
      return opaqueNode(expr);
    }
    final spec = _resolveSpec(call);
    if (spec == null) {
      return opaqueNode(expr);
    }
    return _buildModeledFromCall(call, spec);
  }

  /// Resolves the `CatalogSpec` for [call] across both unnamed-ctor and
  /// named-ctor shapes. For `Class(...)` it's a direct catalog lookup;
  /// for `Class.named(...)` we first find the parent class's spec, then
  /// consult its `namedConstructors` map. Returns null when neither
  /// shape is recognized (the caller falls back to `OpaqueNode`).
  CatalogSpec? _resolveSpec(CallInfo call) {
    if (call.namedConstructor == null) {
      return specFor(call.className);
    }
    final parent = specFor(call.className);
    return parent?.namedConstructors[call.namedConstructor!];
  }

  ModelNode _buildMethodReference(
    MethodInvocation callExpr,
    MethodDeclaration declaration,
  ) {
    final bodyExpr = extractMethodReturnExpression(declaration);
    if (bodyExpr == null) {
      return opaqueNode(callExpr);
    }
    final methodName = declaration.name.lexeme;
    _resolvingMethods.add(methodName);
    try {
      final body = convertNode(bodyExpr);
      return MethodReferenceNode(
        methodName: methodName,
        callSourceSpan: span(callExpr),
        body: body,
      );
    } finally {
      _resolvingMethods.remove(methodName);
    }
  }

  OpaqueNode opaqueNode(SyntacticEntity entity) {
    final s = span(entity);
    return OpaqueNode(
      sourceSpan: s,
      sourceText: source.substring(s.offset, s.offset + s.length),
    );
  }

  OpaquePropertyValue opaqueProperty(SyntacticEntity entity) {
    final s = span(entity);
    return OpaquePropertyValue(
      span: s,
      sourceText: source.substring(s.offset, s.offset + s.length),
    );
  }

  ModelNode _buildModeledFromCall(CallInfo call, CatalogSpec spec) {
    final properties = <String, PropertyValue>{};
    final childSlots = <String, List<ModelNode>>{};
    final childSlotStyles = <String, ListSlotStyle>{};

    final args = call.argumentList.arguments;
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (arg is NamedArgument) {
        // analyzer 13+: named args wrap the inner expression. The name is
        // a single `Token` (was `Label { label: SimpleIdentifier }` in
        // older analyzers — flattened in the AST refactor).
        final name = arg.name.lexeme;
        final slotShape = spec.childSlots[name];
        if (slotShape != null) {
          final slot = _collectChildSlot(arg.argumentExpression, slotShape);
          childSlots[name] = slot.children;
          if (slot.style != null) {
            childSlotStyles[name] = slot.style!;
          }
        } else {
          properties[name] = convertProperty(arg.argumentExpression);
        }
      } else if (arg is Expression) {
        // Positional: `Expression implements Argument` in analyzer 13+,
        // so a non-`NamedArgument` arg IS the positional expression
        // itself (no wrapper).
        final propName = spec.positionalToProperty[i];
        if (propName == null) {
          // Unmodeled positional argument: capture as an opaque property
          // under a synthetic key built from `kPositionalOpaqueKeyPrefix`
          // plus the source index. The serializer recognizes this prefix
          // and re-emits the value as a positional argument at the same
          // index, interleaved with any catalog-modeled positionals.
          properties['$kPositionalOpaqueKeyPrefix$i'] = opaqueProperty(arg);
        } else {
          properties[propName] = convertProperty(arg);
        }
      }
    }

    return buildModeledNode(
      className: call.className,
      namedConstructor: call.namedConstructor,
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
        // a method call returning a list). Wrap the whole thing as a
        // single opaque entry, and crucially do NOT synthesize a
        // ListSlotStyle: there is no real bracketed list literal here,
        // so structural edits must not target this slot.
        return (children: <ModelNode>[opaqueNode(slotExpr)], style: null);
      }
      final children = <ModelNode>[];
      for (final element in slotExpr.elements) {
        if (element is Expression) {
          children.add(convertNode(element));
        } else {
          // Spread or if/for collection element: opaque.
          children.add(opaqueNode(element));
        }
      }
      return (children: children, style: _listStyle(slotExpr));
    }
    return (children: <ModelNode>[convertNode(slotExpr)], style: null);
  }

  ListSlotStyle _listStyle(ListLiteral list) {
    final left = list.leftBracket;
    final right = list.rightBracket;
    final s = SourceSpan(
      offset: left.offset,
      length: right.offset + right.length - left.offset,
    );
    final tokenBeforeRight = right.previous;
    final hasTrailingComma =
        tokenBeforeRight != null && tokenBeforeRight.lexeme == ',';
    final interior = source.substring(left.offset + left.length, right.offset);
    final isMultiLine = interior.contains('\n');
    return ListSlotStyle(
      bracketsSpan: s,
      hasTrailingComma: hasTrailingComma,
      isMultiLine: isMultiLine,
    );
  }

  /// Converts an expression at a property position to a `PropertyValue`.
  /// Standard literal kinds (string, num, bool, null, prefixed-identifier)
  /// are handled here; anything outside that set is offered to the
  /// `customConstructorPropertyValue` hook before falling through to opaque.
  PropertyValue convertProperty(Expression expr) {
    if (expr is SimpleStringLiteral) {
      // Raw (`r'...'`) and triple-quoted (`'''...'''`) strings have surface
      // forms the kernel doesn't model; route them to opaque so their
      // bytes survive verbatim.
      if (expr.isRaw || expr.isMultiline) {
        return opaqueProperty(expr);
      }
      return StringLiteralValue(
        value: expr.value,
        usesDoubleQuotes: !expr.isSingleQuoted,
        span: span(expr),
      );
    }
    if (expr is IntegerLiteral) {
      final value = expr.value;
      if (value != null) {
        return NumLiteralValue(
          value: value,
          isDouble: false,
          span: span(expr),
        );
      }
    }
    if (expr is DoubleLiteral) {
      return NumLiteralValue(
        value: expr.value,
        isDouble: true,
        span: span(expr),
      );
    }
    if (expr is BooleanLiteral) {
      return BoolLiteralValue(value: expr.value, span: span(expr));
    }
    if (expr is NullLiteral) {
      return NullLiteralValue(span: span(expr));
    }
    // Negative numeric literals: `EdgeInsets.only(left: -8)` is parsed as
    // `PrefixExpression(-, IntegerLiteral(8))` rather than a single signed
    // literal. Recognize this shape so the editor can show / edit a numeric
    // inspector. Other prefix ops (`+`, `!`, `~`, `--`) fall through to opaque.
    if (expr is PrefixExpression && expr.operator.lexeme == '-') {
      final operand = expr.operand;
      if (operand is IntegerLiteral) {
        final v = operand.value;
        if (v != null) {
          return NumLiteralValue(
            value: -v,
            isDouble: false,
            span: span(expr),
          );
        }
      }
      if (operand is DoubleLiteral) {
        return NumLiteralValue(
          value: -operand.value,
          isDouble: true,
          span: span(expr),
        );
      }
    }
    if (expr is PrefixedIdentifier) {
      return EnumReferenceValue(
        typeName: expr.prefix.name,
        memberName: expr.identifier.name,
        span: span(expr),
      );
    }
    // Subclass hook: domain-specific constructor-property recognition.
    final call = tryExtractCall(expr);
    if (call != null) {
      final custom = customConstructorPropertyValue(call);
      if (custom != null) {
        return custom;
      }
    }
    return opaqueProperty(expr);
  }

  StyleHints _hintsFromCall(CallInfo call) {
    final kw = call.keyword?.keyword;
    final argList = call.argumentList;
    final leftParen = argList.leftParenthesis;
    final rightParen = argList.rightParenthesis;
    final prev = rightParen.previous;
    final hasTrailingComma = prev != null && prev.lexeme == ',';
    // Multi-line: the argument list spans more than one source line.
    // Determined by checking whether the source range from `(` to `)`
    // contains a newline. Cheaper than threading LineInfo through every
    // visitor and exactly captures what the editor needs (whether the
    // user wrote a "tall" call versus a "wide" one).
    final spanStart = leftParen.offset;
    final spanEnd = rightParen.end;
    final isMultiLine = source.substring(spanStart, spanEnd).contains('\n');
    return StyleHints(
      hasConst: kw == Keyword.CONST,
      hasNew: kw == Keyword.NEW,
      hasTrailingComma: hasTrailingComma,
      isMultiLine: isMultiLine,
    );
  }

  SourceSpan span(SyntacticEntity entity) =>
      SourceSpan(offset: entity.offset, length: entity.length);

  /// Normalizes the two AST shapes a constructor-call-without-resolution
  /// can take: `InstanceCreationExpression` when `const`/`new` is present,
  /// else `MethodInvocation`. Returns null for anything else.
  ///
  /// Type-argumented calls (`Foo<int>(...)`, `Foo.named<int>(...)`,
  /// `f.method<int>(...)`) deliberately return null so the caller falls
  /// back to `OpaqueNode`. The serializer doesn't carry type-argument
  /// information through the model, so a modeled type-argumented call
  /// would silently drop the `<...>` on re-emission — a round-trip
  /// violation. Opaque preserves the bytes verbatim.
  CallInfo? tryExtractCall(Expression expr) {
    if (expr is InstanceCreationExpression) {
      final type = expr.constructorName.type;
      // `Foo<T>(...)` / `Foo<T>.named(...)`: opaque (see above).
      if (type.typeArguments != null) {
        return null;
      }
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
      return CallInfo(
        className: className,
        namedConstructor: namedConstructor,
        argumentList: expr.argumentList,
        keyword: expr.keyword,
        span: span(expr),
      );
    }
    if (expr is MethodInvocation) {
      // `foo<T>(...)` / `Foo.named<T>(...)`: opaque (see above).
      if (expr.typeArguments != null) {
        return null;
      }
      final target = expr.target;
      if (target == null) {
        return CallInfo(
          className: expr.methodName.name,
          namedConstructor: null,
          argumentList: expr.argumentList,
          keyword: null,
          span: span(expr),
        );
      }
      if (target is SimpleIdentifier) {
        return CallInfo(
          className: target.name,
          namedConstructor: expr.methodName.name,
          argumentList: expr.argumentList,
          keyword: null,
          span: span(expr),
        );
      }
    }
    return null;
  }
}
