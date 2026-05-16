import 'package:analyzer/dart/ast/ast.dart';

import '../catalog/widget_catalog.dart';

/// Walks the top-level class declarations of [unit] and returns a map of
/// class-name → `WidgetSpec` for every class whose `extends` clause names
/// a superclass ending in `Widget` (`StatelessWidget`, `StatefulWidget`,
/// `ConsumerWidget`, `HookWidget`, `InheritedWidget`, `RenderObjectWidget`,
/// `PreferredSizeWidget`, etc.).
///
/// Each returned `WidgetSpec` carries child slots inferred from the class's
/// primary constructor (unnamed if present; first named otherwise). A named
/// parameter typed exactly `Widget` (or `Widget?`) becomes a `single` slot;
/// a parameter typed exactly `List<Widget>` (or `List<Widget>?`) becomes a
/// `list` slot. Inference is name-based and conservative — typedef aliases
/// like `WidgetBuilder` (which is `Widget Function(BuildContext)`) are NOT
/// recognized as slots because we can't resolve the typedef without semantic
/// analysis. This is intentional: a false-negative (treating a real child
/// slot as a property) is harmless; a false-positive (treating a builder
/// callback as a child slot) would break the visitor's recursion.
///
/// Limitations:
///   * Only direct `extends Foo` matches. Transitive widget bases (a class
///     that extends `_PrivateBase` where `_PrivateBase extends StatelessWidget`)
///     are NOT recognized — we don't follow chains without resolved types.
///   * `State<X>`-extending classes are explicitly excluded — they have a
///     `build()` method but aren't themselves widgets to be referenced.
///   * Cross-file widget discovery (recognizing `MyImportedWidget` from
///     another file) is a separate phase that needs `ProjectModel`.
///   * `super.child` (super-formal parameter) is NOT followed to the
///     superclass declaration — we'd need cross-class lookup. Such params
///     are silently skipped (not classified as slots).
Map<String, WidgetSpec> discoverIntraFileWidgets(CompilationUnit unit) {
  final discovered = <String, WidgetSpec>{};
  for (final decl in unit.declarations) {
    if (decl is! ClassDeclaration) continue;
    final extendsClause = decl.extendsClause;
    if (extendsClause == null) continue;
    final superTypeName = extendsClause.superclass.name.lexeme;
    if (_looksLikeWidgetBase(superTypeName)) {
      discovered[decl.namePart.typeName.lexeme] = _inferSpec(decl);
    }
  }
  return discovered;
}

WidgetSpec _inferSpec(ClassDeclaration cls) {
  final ctor = _primaryConstructor(cls);
  if (ctor == null) return const WidgetSpec();

  // Build a name → declared-type index over the class's fields, so we can
  // resolve `this.fieldName` parameters to the corresponding field type.
  final fieldTypes = <String, TypeAnnotation>{};
  for (final member in cls.body.members) {
    if (member is! FieldDeclaration) continue;
    final declaredType = member.fields.type;
    if (declaredType == null) continue;
    for (final v in member.fields.variables) {
      fieldTypes[v.name.lexeme] = declaredType;
    }
  }

  final slots = <String, ChildSlotShape>{};
  for (final param in ctor.parameters.parameters) {
    final name = param.name?.lexeme;
    if (name == null) continue;
    final type = _effectiveParamType(param, fieldTypes);
    if (type == null) continue;
    final shape = _slotShapeFor(type);
    if (shape != null) {
      slots[name] = shape;
    }
  }
  return WidgetSpec(childSlots: slots);
}

ConstructorDeclaration? _primaryConstructor(ClassDeclaration cls) {
  ConstructorDeclaration? firstNamed;
  for (final member in cls.body.members) {
    if (member is! ConstructorDeclaration) continue;
    // The unnamed constructor (no `.name` after the class name) is the
    // primary; prefer it over any named alternative.
    if (member.name == null) return member;
    firstNamed ??= member;
  }
  return firstNamed;
}

TypeAnnotation? _effectiveParamType(
  FormalParameter param,
  Map<String, TypeAnnotation> fieldTypes,
) {
  // Function-typed shorthand (`Widget child(BuildContext c)`) — not a slot.
  // The `functionTypedSuffix` token is non-null in that form regardless of
  // whether the declared `.type` looks widget-shaped.
  if (param.functionTypedSuffix != null) return null;

  // `super.key` and similar — we don't follow super to find the type.
  if (param is SuperFormalParameter) return null;

  if (param is FieldFormalParameter) {
    // `this.child` — type is either explicit (rare: `Widget this.child`) or
    // taken from the matching field declaration in this class.
    final name = param.name.lexeme;
    return param.type ?? fieldTypes[name];
  }

  // RegularFormalParameter (and anything else exposing `.type` via the
  // FormalParameter base).
  return param.type;
}

ChildSlotShape? _slotShapeFor(TypeAnnotation type) {
  // Function types (`Widget Function(BuildContext)`) — not a slot.
  if (type is! NamedType) return null;
  final name = type.name.lexeme;
  if (name == 'Widget') return ChildSlotShape.single;
  if (name == 'List') {
    final args = type.typeArguments?.arguments;
    if (args != null && args.length == 1) {
      final inner = args.first;
      if (inner is NamedType && inner.name.lexeme == 'Widget') {
        return ChildSlotShape.list;
      }
    }
  }
  return null;
}

bool _looksLikeWidgetBase(String superName) {
  // Primary heuristic: ends in "Widget". Catches all framework widget
  // bases that follow the convention (`StatelessWidget`, `StatefulWidget`,
  // `InheritedWidget`, `RenderObjectWidget`, `LeafRenderObjectWidget`,
  // `MultiChildRenderObjectWidget`, `SingleChildRenderObjectWidget`,
  // `ProxyWidget`, `PreferredSizeWidget`, `ComponentWidget`) plus
  // third-party bases that follow the same naming (`ConsumerWidget`,
  // `HookWidget`, `ConsumerStatefulWidget`, `StatefulHookConsumerWidget`).
  //
  // Crucially, `State<X>` does NOT end in "Widget", so the State half of a
  // StatefulWidget pair is excluded — we register the StatefulWidget itself,
  // not its State.
  if (superName.endsWith('Widget')) return true;

  // Allowlist of common framework widget bases that DON'T end in "Widget"
  // despite being widget subclasses. Each transitively extends Widget;
  // without resolved types we can't follow that chain across packages, so
  // we hardcode the publicly-known cases that come up in real code.
  return _knownNonWidgetSuffixBases.contains(superName);
}

const Set<String> _knownNonWidgetSuffixBases = <String>{
  // All extend InheritedWidget transitively.
  'InheritedNotifier',
  'InheritedTheme',
  'InheritedModel',
};
