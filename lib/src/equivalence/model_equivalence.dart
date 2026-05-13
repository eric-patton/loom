import '../model/list_slot_style.dart';
import '../model/property_value.dart';
import '../model/widget_node.dart';

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

  /// Compares two model nodes structurally. Different concrete types
  /// (one `WidgetNode`, one `OpaqueNode`) are never equivalent.
  static bool nodesEqual(ModelNode a, ModelNode b) => _modelNodesEqual(a, b);

  /// Compares two `PropertyValue`s semantically (value-level), ignoring
  /// source spans. `OpaquePropertyValue`s compare by their captured
  /// source text.
  static bool propertiesEqual(PropertyValue a, PropertyValue b) =>
      switch ((a, b)) {
        (final StringLiteralValue a, final StringLiteralValue b) =>
          a.value == b.value,
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

bool _modelNodesEqual(ModelNode a, ModelNode b) => switch ((a, b)) {
      (final WidgetNode a, final WidgetNode b) => _widgetNodesEqual(a, b),
      (final OpaqueNode a, final OpaqueNode b) => a.sourceText == b.sourceText,
      _ => false,
    };

bool _widgetNodesEqual(WidgetNode a, WidgetNode b) {
  if (a.className != b.className) {
    return false;
  }
  if (a.styleHints != b.styleHints) {
    return false;
  }
  if (a.properties.length != b.properties.length) {
    return false;
  }
  for (final entry in a.properties.entries) {
    final other = b.properties[entry.key];
    if (other == null) {
      return false;
    }
    if (!StructuralEquivalence.propertiesEqual(entry.value, other)) {
      return false;
    }
  }
  if (a.childSlots.length != b.childSlots.length) {
    return false;
  }
  for (final entry in a.childSlots.entries) {
    final otherSlot = b.childSlots[entry.key];
    if (otherSlot == null) {
      return false;
    }
    if (entry.value.length != otherSlot.length) {
      return false;
    }
    for (var i = 0; i < entry.value.length; i++) {
      if (!_modelNodesEqual(entry.value[i], otherSlot[i])) {
        return false;
      }
    }
  }
  if (a.childSlotStyles.length != b.childSlotStyles.length) {
    return false;
  }
  for (final entry in a.childSlotStyles.entries) {
    final otherStyle = b.childSlotStyles[entry.key];
    if (otherStyle == null) {
      return false;
    }
    // Empty lists may differ in isMultiLine/hasTrailingComma after
    // emptying (e.g., a multi-line `[\n  a,\n]` contracts to `[]` when
    // the only element is removed). Skip style comparison when the
    // corresponding slot is empty on both sides.
    final aSlotEmpty = (a.childSlots[entry.key] ?? const <ModelNode>[]).isEmpty;
    final bSlotEmpty = (b.childSlots[entry.key] ?? const <ModelNode>[]).isEmpty;
    if (aSlotEmpty && bSlotEmpty) {
      continue;
    }
    if (!StructuralEquivalence.listSlotStylesEqual(entry.value, otherStyle)) {
      return false;
    }
  }
  return true;
}
