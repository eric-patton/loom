import '../model/list_slot_style.dart';
import '../model/node.dart';
import '../model/property_value.dart';
import 'list_edit_helpers.dart';
import 'pipeline_serializer.dart';
import 'property_serializer.dart';
import 'source_edit.dart';

/// Plans `SourceEdit`s for individual pipeline-model changes. Sibling of
/// `EditPlanner` (widget) and `RouteEditPlanner` (route). Same per-domain
/// glue shape: validate against the `PipelineNode` parent, pick the slot
/// style + children list, delegate to [ListEditHelpers] for the byte-level
/// edit. Insert paths serialize new children via [PipelineSerializer].
class PipelineEditPlanner {
  PipelineEditPlanner._();

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

  static SourceEdit insertChildEdit({
    required PipelineNode parent,
    required String slotName,
    required int index,
    required ModelNode newChild,
    required String source,
  }) =>
      ListEditHelpers.insertAt(
        slotStyle: _requireListStyle(parent, slotName),
        children: parent.childSlots[slotName] ?? const <ModelNode>[],
        index: index,
        newSourceText: PipelineSerializer.serialize(newChild),
        source: source,
      );

  static SourceEdit removeChildEdit({
    required PipelineNode parent,
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

  static List<SourceEdit> moveChildEdits({
    required PipelineNode parent,
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

  static ListSlotStyle _requireListStyle(
    PipelineNode parent,
    String slotName,
  ) {
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
