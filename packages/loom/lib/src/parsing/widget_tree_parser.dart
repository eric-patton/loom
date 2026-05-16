import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

import '../catalog/widget_catalog.dart';
import '../model/source_span.dart';
import '../model/node.dart';
import 'project_widget_discovery.dart';
import 'widget_visitor.dart';

/// Parses a Dart source string into a `WidgetTreeModel`.
///
/// M1 scope: finds the first `ClassDeclaration` containing a method named
/// `build` whose body returns a widget tree, then walks that return
/// expression. Imports and other top-level constructs are not modeled — see
/// Settled Decisions Q5 in DEVLOG.md.
///
/// [projectWidgets] supplies cross-file user widgets — typically the
/// result of `ProjectWidgetIndex.widgetsVisibleFrom(filePath)`. Intra-file
/// discoveries always win on name collisions (more specific scope). Pass
/// an empty map (the default) for single-file parsing.
WidgetTreeModel parseWidgetTree(
  String source, {
  Map<String, WidgetSpec> projectWidgets = const <String, WidgetSpec>{},
}) {
  final result = parseString(content: source, throwIfDiagnostics: false);
  final unit = result.unit;
  final diagnostics = <ParseDiagnostic>[
    for (final error in result.errors)
      ParseDiagnostic(
        span: SourceSpan(offset: error.offset, length: error.length),
        message: error.message,
      ),
  ];

  // Pre-pass: discover project-defined widget classes (anything extending
  // a `*Widget` base) in this unit. Merge with cross-file project widgets;
  // intra-file declarations win on collisions (Dart's import-clash rules
  // would be an error in that case anyway).
  final intraFileWidgets = discoverIntraFileWidgets(unit);
  final localCatalog = <String, WidgetSpec>{
    ...projectWidgets,
    ...intraFileWidgets,
  };

  for (final declaration in unit.declarations) {
    if (declaration is! ClassDeclaration) {
      continue;
    }

    // Index in-class methods (other than `build`) so the visitor can
    // resolve helper-method calls (M5). All non-`build` methods are
    // included; the visitor restricts resolution to no-arg calls.
    final classMethods = <String, MethodDeclaration>{};
    MethodDeclaration? buildMethod;
    for (final member in declaration.body.members) {
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
      localCatalog: localCatalog,
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
    final visitor = WidgetVisitor(
      source,
      classMethods: safeMethods,
      localCatalog: localCatalog,
    );
    return WidgetTreeModel(
      root: visitor.convertNode(root),
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
/// can't reach `convertNode` in the visitor and so don't contribute
/// to multi-reference risk. Without this widget-position filter the
/// counter over-counted (e.g. `_a()` inside `_a().wrap()` looked like a
/// helper reference even though the visitor would never resolve it as
/// such).
Map<String, int> _countMethodReferences({
  required Set<String> knownMethods,
  required Iterable<MethodDeclaration> methods,
  required Map<String, WidgetSpec> localCatalog,
}) {
  final counter = _ReferenceCounter(knownMethods, localCatalog);
  for (final method in methods) {
    final expr = extractMethodReturnExpression(method);
    if (expr != null) {
      counter._countAtWidgetPosition(expr);
    }
  }
  return counter.counts;
}

class _ReferenceCounter {
  _ReferenceCounter(this._knownMethods, this._localCatalog);

  final Set<String> _knownMethods;
  final Map<String, WidgetSpec> _localCatalog;
  final Map<String, int> counts = <String, int>{};

  void _countAtWidgetPosition(Expression expr) {
    // Mirror `BaseVisitor.convertNode`: a no-target, no-arg,
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
    // Match the visitor's lookup order: framework catalog wins, otherwise
    // fall back to project-discovered widgets. Without this, helpers nested
    // inside a user widget's inferred `child:` slot would be undercounted —
    // the visitor would still create MethodReferenceNodes for them, leading
    // to multi-reference divergence on edit.
    final spec =
        WidgetCatalog.specFor(call.className) ?? _localCatalog[call.className];
    if (spec == null) {
      return;
    }
    for (final arg in call.argumentList.arguments) {
      if (arg is! NamedArgument) {
        continue;
      }
      final shape = spec.childSlots[arg.name.lexeme];
      if (shape == null) {
        continue;
      }
      _countInSlot(arg.argumentExpression, shape);
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
      final className = type.importPrefix?.name.lexeme ?? type.name.lexeme;
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
