import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

import '../catalog/widget_catalog.dart';
import '../model/source_span.dart';
import '../model/widget_node.dart';
import 'widget_visitor.dart';

/// Experimental Dart language features we explicitly opt into when
/// calling `parseString`. The `analyzer` package dep is pinned at
/// `^7.3.0` (the `_macros` SDK-conflict workaround), which lags behind
/// the bundled-SDK analyzer in some recent language additions. Without
/// these flags, real-world Flutter source on Dart 3.10+ surfaces
/// false-positive "this requires the X language feature" diagnostics
/// even though the SDK's own analyzer parses them cleanly.
///
/// Adding a flag here is safe: the kernel falls back to `OpaqueNode`
/// for any AST shape the visitor doesn't recognize, so new syntax that
/// lands as a node type we don't model just round-trips its bytes
/// verbatim. The list below is what the scout against flutter/codelabs
/// surfaced; add to it as future scouts find more.
const _enabledExperimentalFlags = <String>[
  'dot-shorthands',
  'digit-separators',
  'null-aware-elements',
  'wildcard-variables',
];

/// Parses a Dart source string into a `WidgetTreeModel`.
///
/// M1 scope: finds the first `ClassDeclaration` containing a method named
/// `build` whose body returns a widget tree, then walks that return
/// expression. Imports and other top-level constructs are not modeled — see
/// Settled Decisions Q5 in DEVLOG.md.
WidgetTreeModel parseWidgetTree(String source) {
  final result = parseString(
    content: source,
    throwIfDiagnostics: false,
    featureSet: FeatureSet.latestLanguageVersion(
      flags: _enabledExperimentalFlags,
    ),
  );
  final unit = result.unit;
  final diagnostics = <ParseDiagnostic>[
    for (final error in result.errors)
      ParseDiagnostic(
        span: SourceSpan(offset: error.offset, length: error.length),
        message: error.message,
      ),
  ];

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
    // body for argumentless no-target calls to in-class methods that
    // occur at *widget positions* (the only positions the visitor
    // would resolve into `MethodReferenceNode`). Helpers invoked from
    // more than one widget position can't be safely represented as
    // `MethodReferenceNode` — an in-memory edit through one reference
    // would diverge from the reparsed model (which sees the helper-
    // source change reflected at every call site). Such helpers are
    // removed from the lookup map, so the visitor emits `OpaqueNode`
    // for every reference.
    final referenceCounts = _countMethodReferences(
      knownMethods: classMethods.keys.toSet(),
      methods: [buildMethod, ...classMethods.values],
    );
    final safeMethods = <String, MethodDeclaration>{
      for (final entry in classMethods.entries)
        if ((referenceCounts[entry.key] ?? 0) <= 1) entry.key: entry.value,
    };

    final root = extractMethodReturnExpression(buildMethod);
    if (root == null) {
      throw const ParseException(
        'build() found but has no return expression',
      );
    }
    final visitor = WidgetVisitor(source, classMethods: safeMethods);
    return WidgetTreeModel(
      root: visitor.convertModelNode(root),
      diagnostics: diagnostics,
    );
  }

  throw const ParseException(
    'No build() method found in any class declaration',
  );
}

/// Walks each method's return expression as the visitor would and returns,
/// for each name in `knownMethods`, how many widget-position references
/// to that method it found. Property values, opaque expressions, method-
/// call targets, and positional arguments are NOT recursed into — they
/// can't reach `convertModelNode` in the visitor and so don't contribute
/// to multi-reference risk. Without this widget-position filter the
/// counter over-counted (e.g. `_a()` inside `_a().wrap()` looked like a
/// helper reference even though the visitor would never resolve it as
/// such).
Map<String, int> _countMethodReferences({
  required Set<String> knownMethods,
  required Iterable<MethodDeclaration> methods,
}) {
  final counter = _ReferenceCounter(knownMethods);
  for (final method in methods) {
    final expr = extractMethodReturnExpression(method);
    if (expr != null) {
      counter._countAtWidgetPosition(expr);
    }
  }
  return counter.counts;
}

class _ReferenceCounter {
  _ReferenceCounter(this._knownMethods);

  final Set<String> _knownMethods;
  final Map<String, int> counts = <String, int>{};

  void _countAtWidgetPosition(Expression expr) {
    // Mirror `WidgetVisitor.convertModelNode`: a no-target, no-arg,
    // no-type-args call that matches a known method is what would be
    // resolved as `MethodReferenceNode`. Count and stop — we don't
    // descend into the helper's body here; that's walked separately
    // when the counter iterates the helper's MethodDeclaration.
    if (expr is MethodInvocation &&
        expr.target == null &&
        expr.typeArguments == null &&
        expr.argumentList.arguments.isEmpty) {
      final name = expr.methodName.name;
      if (_knownMethods.contains(name)) {
        counts.update(name, (n) => n + 1, ifAbsent: () => 1);
        return;
      }
    }
    // Otherwise: treat as a possible constructor invocation. Recurse
    // into named-arg expressions for catalog-known child slots; skip
    // property values, positional args, and unknown widgets (the
    // visitor treats those as leaves / opaque, so the counter must
    // too).
    final call = _extractCall(expr);
    if (call == null) {
      return;
    }
    final spec = WidgetCatalog.specFor(call.className);
    if (spec == null) {
      return;
    }
    for (final arg in call.argumentList.arguments) {
      if (arg is! NamedExpression) {
        continue;
      }
      final shape = spec.childSlots[arg.name.label.name];
      if (shape == null) {
        continue;
      }
      _countInSlot(arg.expression, shape);
    }
  }

  void _countInSlot(Expression slotExpr, ChildSlotShape shape) {
    if (shape == ChildSlotShape.list) {
      if (slotExpr is! ListLiteral) {
        // Non-list expression in a list slot: visitor records this as
        // a single OpaqueNode and discards the inside. Don't recurse.
        return;
      }
      for (final element in slotExpr.elements) {
        if (element is Expression) {
          _countAtWidgetPosition(element);
        }
        // Spread / if / for collection elements: opaque; don't recurse.
      }
    } else {
      _countAtWidgetPosition(slotExpr);
    }
  }

  _CallShape? _extractCall(Expression expr) {
    if (expr is InstanceCreationExpression) {
      final type = expr.constructorName.type;
      final className = type.importPrefix?.name.lexeme ?? type.name2.lexeme;
      return _CallShape(className, expr.argumentList);
    }
    if (expr is MethodInvocation) {
      final target = expr.target;
      if (target == null) {
        return _CallShape(expr.methodName.name, expr.argumentList);
      }
      if (target is SimpleIdentifier) {
        // `Class.named(...)` form. Class name is the target.
        return _CallShape(target.name, expr.argumentList);
      }
    }
    return null;
  }
}

class _CallShape {
  _CallShape(this.className, this.argumentList);
  final String className;
  final ArgumentList argumentList;
}
