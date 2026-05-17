import '../model/list_slot_style.dart';
import '../model/property_value.dart';
import '../model/style_hints.dart';
import '../model/node.dart';

/// Structural model equivalence — the oracle the round-trip property test
/// uses to verify `parse(apply(emit(M, edits), source))` matches the
/// expected post-edit model.
///
/// Q3 Settled Decision (DEVLOG): ignores source spans (which shift in
/// re-parsed source even when structure is identical), but preserves
/// const-vs-non-const distinctions and explicit `new` keywords via the
/// `StyleHints` comparison. The model itself is already trivia-blind by
/// construction — whitespace and comments do not enter the model — so
/// field-by-field recursive equality on the model IS the spec's described
/// AST equivalence, just at a cheaper layer.
///
/// `OpaqueNode`s compare by their `sourceText` (the verbatim bytes),
/// since opaque content has no model-level structure to recurse into.
/// Two opaque regions with identical bytes are equivalent regardless of
/// where they appear in their respective sources.
class StructuralEquivalence {
  StructuralEquivalence._();

  static bool equal(WidgetTreeModel a, WidgetTreeModel b) =>
      _modelNodesEqual(a.root, b.root);

  /// Same as [equal] but for `RouteTreeModel`. Routes share the same
  /// constructor-call shape as widgets (`RouteNode` mirrors `WidgetNode`)
  /// so the same node-comparison engine handles them.
  static bool equalRoutes(RouteTreeModel a, RouteTreeModel b) =>
      _modelNodesEqual(a.root, b.root);

  /// Same as [equal] but for `PipelineTreeModel`.
  static bool equalPipelines(PipelineTreeModel a, PipelineTreeModel b) =>
      _modelNodesEqual(a.root, b.root);

  /// Compares two model nodes structurally. Different concrete types
  /// (one `WidgetNode`, one `OpaqueNode`) are never equivalent.
  static bool nodesEqual(ModelNode a, ModelNode b) => _modelNodesEqual(a, b);

  /// Compares two `PropertyValue`s semantically (value-level), ignoring
  /// source spans. `OpaquePropertyValue`s compare by their captured
  /// source text.
  static bool propertiesEqual(PropertyValue a, PropertyValue b) =>
      switch ((a, b)) {
        (final StringLiteralValue a, final StringLiteralValue b) =>
          a.value == b.value && a.usesDoubleQuotes == b.usesDoubleQuotes,
        (final NumLiteralValue a, final NumLiteralValue b) =>
          a.value == b.value && a.isDouble == b.isDouble,
        (final BoolLiteralValue a, final BoolLiteralValue b) =>
          a.value == b.value,
        (NullLiteralValue _, NullLiteralValue _) => true,
        (final EdgeInsetsAllValue a, final EdgeInsetsAllValue b) =>
          a.amount == b.amount && a.amountIsDouble == b.amountIsDouble,
        (final ColorValue a, final ColorValue b) => a.argbValue == b.argbValue,
        (final EnumReferenceValue a, final EnumReferenceValue b) =>
          a.typeName == b.typeName && a.memberName == b.memberName,
        (final OpaquePropertyValue a, final OpaquePropertyValue b) =>
          a.sourceText == b.sourceText,
        _ => false,
      };

  /// Compares two `ListSlotStyle`s by their structural shape only —
  /// `hasTrailingComma` and `isMultiLine`. `bracketsSpan` is ignored
  /// because spans shift across re-parses of edited source.
  static bool listSlotStylesEqual(ListSlotStyle a, ListSlotStyle b) =>
      a.hasTrailingComma == b.hasTrailingComma &&
      a.isMultiLine == b.isMultiLine;
}

bool _modelNodesEqual(ModelNode a, ModelNode b) {
  // Reject mismatched concrete types up-front. The switch below would do
  // the same (each (Same, Same) case checks both halves), but pre-checking
  // the runtime types makes the type-narrowing inside the switch arms
  // easier to follow and keeps a hypothetical future sealed addition from
  // silently being equal to itself by default.
  if (a.runtimeType != b.runtimeType) return false;
  return switch (a) {
    final WidgetNode a => _constructorCallNodesEqual(
        className: a.className,
        namedConstructor: a.namedConstructor,
        styleHints: a.styleHints,
        properties: a.properties,
        childSlots: a.childSlots,
        childSlotStyles: a.childSlotStyles,
        otherClassName: (b as WidgetNode).className,
        otherNamedConstructor: b.namedConstructor,
        otherStyleHints: b.styleHints,
        otherProperties: b.properties,
        otherChildSlots: b.childSlots,
        otherChildSlotStyles: b.childSlotStyles,
      ),
    final RouteNode a => _constructorCallNodesEqual(
        className: a.className,
        namedConstructor: a.namedConstructor,
        styleHints: a.styleHints,
        properties: a.properties,
        childSlots: a.childSlots,
        childSlotStyles: a.childSlotStyles,
        otherClassName: (b as RouteNode).className,
        otherNamedConstructor: b.namedConstructor,
        otherStyleHints: b.styleHints,
        otherProperties: b.properties,
        otherChildSlots: b.childSlots,
        otherChildSlotStyles: b.childSlotStyles,
      ),
    final PipelineNode a => _constructorCallNodesEqual(
        className: a.className,
        namedConstructor: a.namedConstructor,
        styleHints: a.styleHints,
        properties: a.properties,
        childSlots: a.childSlots,
        childSlotStyles: a.childSlotStyles,
        otherClassName: (b as PipelineNode).className,
        otherNamedConstructor: b.namedConstructor,
        otherStyleHints: b.styleHints,
        otherProperties: b.properties,
        otherChildSlots: b.childSlots,
        otherChildSlotStyles: b.childSlotStyles,
      ),
    final OpaqueNode a => a.sourceText == (b as OpaqueNode).sourceText,
    final MethodReferenceNode a =>
      a.methodName == (b as MethodReferenceNode).methodName &&
          _modelNodesEqual(a.body, b.body),
  };
}

/// Shared structural-equality engine for the three constructor-call node
/// kinds — `WidgetNode`, `RouteNode`, `PipelineNode`. Their fields are
/// identical in shape, so the same logic compares them. This used to be
/// `_widgetNodesEqual` alone; mirroring the unified visitor architecture
/// (M6.1/6.2), the equivalence oracle is now also domain-agnostic.
bool _constructorCallNodesEqual({
  required String className,
  required String? namedConstructor,
  required StyleHints styleHints,
  required Map<String, PropertyValue> properties,
  required Map<String, List<ModelNode>> childSlots,
  required Map<String, ListSlotStyle> childSlotStyles,
  required String otherClassName,
  required String? otherNamedConstructor,
  required StyleHints otherStyleHints,
  required Map<String, PropertyValue> otherProperties,
  required Map<String, List<ModelNode>> otherChildSlots,
  required Map<String, ListSlotStyle> otherChildSlotStyles,
}) {
  if (className != otherClassName) return false;
  if (namedConstructor != otherNamedConstructor) return false;
  if (styleHints != otherStyleHints) return false;
  if (properties.length != otherProperties.length) return false;
  for (final entry in properties.entries) {
    final other = otherProperties[entry.key];
    if (other == null) return false;
    if (!StructuralEquivalence.propertiesEqual(entry.value, other)) {
      return false;
    }
  }
  if (childSlots.length != otherChildSlots.length) return false;
  for (final entry in childSlots.entries) {
    final otherSlot = otherChildSlots[entry.key];
    if (otherSlot == null) return false;
    if (entry.value.length != otherSlot.length) return false;
    for (var i = 0; i < entry.value.length; i++) {
      if (!_modelNodesEqual(entry.value[i], otherSlot[i])) return false;
    }
  }
  if (childSlotStyles.length != otherChildSlotStyles.length) return false;
  for (final entry in childSlotStyles.entries) {
    final otherStyle = otherChildSlotStyles[entry.key];
    if (otherStyle == null) return false;
    // Empty lists may differ in isMultiLine/hasTrailingComma after
    // emptying (e.g., a multi-line `[\n  a,\n]` contracts to `[]` when
    // the only element is removed). Skip style comparison when the
    // corresponding slot is empty on both sides.
    final aSlotEmpty = (childSlots[entry.key] ?? const <ModelNode>[]).isEmpty;
    final bSlotEmpty =
        (otherChildSlots[entry.key] ?? const <ModelNode>[]).isEmpty;
    if (aSlotEmpty && bSlotEmpty) continue;
    if (!StructuralEquivalence.listSlotStylesEqual(entry.value, otherStyle)) {
      return false;
    }
  }
  return true;
}
