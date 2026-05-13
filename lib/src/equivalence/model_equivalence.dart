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
class StructuralEquivalence {
  StructuralEquivalence._();

  /// Compares two models structurally. Returns `true` iff every
  /// `WidgetNode` matches by className, properties (by name, value
  /// compared semantically), child slots (by slot name and index,
  /// recursively), and style hints.
  static bool equal(WidgetTreeModel a, WidgetTreeModel b) =>
      nodesEqual(a.root, b.root);

  static bool nodesEqual(WidgetNode a, WidgetNode b) {
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
      if (!propertiesEqual(entry.value, other)) {
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
        if (!nodesEqual(entry.value[i], otherSlot[i])) {
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
      final aSlotEmpty =
          (a.childSlots[entry.key] ?? const <WidgetNode>[]).isEmpty;
      final bSlotEmpty =
          (b.childSlots[entry.key] ?? const <WidgetNode>[]).isEmpty;
      if (aSlotEmpty && bSlotEmpty) {
        continue;
      }
      if (!listSlotStylesEqual(entry.value, otherStyle)) {
        return false;
      }
    }
    return true;
  }

  /// Compares two `ListSlotStyle`s by their structural shape only —
  /// `hasTrailingComma` and `isMultiLine`. `bracketsSpan` is ignored
  /// because spans shift across re-parses of edited source.
  static bool listSlotStylesEqual(ListSlotStyle a, ListSlotStyle b) =>
      a.hasTrailingComma == b.hasTrailingComma &&
      a.isMultiLine == b.isMultiLine;

  /// Compares two `PropertyValue`s semantically (value-level), ignoring
  /// source spans.
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
        _ => false,
      };
}
