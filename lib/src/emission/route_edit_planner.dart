import '../model/list_slot_style.dart';
import '../model/node.dart';
import '../model/property_value.dart';
import 'list_edit_helpers.dart';
import 'property_serializer.dart';
import 'route_serializer.dart';
import 'source_edit.dart';

/// Plans `SourceEdit`s for individual route-model changes.
///
/// M6.1 Phase 3 thinned this to per-domain glue: each method validates
/// inputs against the `RouteNode` parent, picks the slot style and
/// children list, then delegates to [ListEditHelpers] for the actual
/// byte-level edit math. Insert paths serialize new children through
/// [RouteSerializer].
class RouteEditPlanner {
  RouteEditPlanner._();

  /// Returns the `SourceEdit` that replaces the source range of
  /// `oldValue` with the serialized form of `newValue`.
  static SourceEdit propertyEdit({
    required PropertyValue oldValue,
    required PropertyValue newValue,
  }) {
    return SourceEdit(
      offset: oldValue.span.offset,
      length: oldValue.span.length,
      replacement: PropertySerializer.serialize(newValue),
    );
  }

  /// Inserts `newChild` at `index` of `parent.childSlots[slotName]`.
  static SourceEdit insertChildEdit({
    required RouteNode parent,
    required String slotName,
    required int index,
    required ModelNode newChild,
    required String source,
  }) =>
      ListEditHelpers.insertAt(
        slotStyle: _requireListStyle(parent, slotName),
        children: parent.childSlots[slotName] ?? const <ModelNode>[],
        index: index,
        newSourceText: RouteSerializer.serialize(newChild),
        source: source,
      );

  /// Removes the child at `index` of `parent.childSlots[slotName]`.
  static SourceEdit removeChildEdit({
    required RouteNode parent,
    required String slotName,
    required int index,
    required String source,
  }) =>
      ListEditHelpers.removeAt(
        slotStyle: _requireListStyle(parent, slotName),
        children: parent.childSlots[slotName] ?? const <ModelNode>[],
        index: index,
        source: source,
      );

  /// Moves the child at `from` to position `to` in the same slot.
  static List<SourceEdit> moveChildEdits({
    required RouteNode parent,
    required String slotName,
    required int from,
    required int to,
    required String source,
  }) =>
      ListEditHelpers.moveBetween(
        slotStyle: _requireListStyle(parent, slotName),
        children: parent.childSlots[slotName] ?? const <ModelNode>[],
        from: from,
        to: to,
        source: source,
      );

  static ListSlotStyle _requireListStyle(RouteNode parent, String slotName) {
    final style = parent.childSlotStyles[slotName];
    if (style == null) {
      throw ArgumentError(
        '${parent.className}.$slotName is not a list-shaped slot or its '
        'style was not captured; cannot plan a structural edit.',
      );
    }
    return style;
  }
}
