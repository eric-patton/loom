import 'property_value.dart';
import 'widget_node.dart';

/// One step along a path through the model: which child slot to descend
/// into, and which index within that slot.
typedef NodePathSegment = ({String slot, int index});

/// A path from the model's root to a specific node, expressed as a
/// sequence of (slot, index) descents. The empty list points at the root.
typedef NodePath = List<NodePathSegment>;

extension NodeNavigation on WidgetTreeModel {
  /// Returns the node reached by following `path`, or `null` if the path
  /// is invalid (unknown slot or out-of-range index).
  WidgetNode? nodeAt(NodePath path) => _nodeAt(root, path);

  /// Returns a new model with the property at `path / propName` replaced
  /// by `value`. Other parts of the tree are structurally unchanged
  /// (and physically reused where possible since `WidgetNode` is immutable).
  WidgetTreeModel withProperty(
    NodePath path,
    String propName,
    PropertyValue value,
  ) =>
      WidgetTreeModel(root: _withProperty(root, path, propName, value));

  /// Walks the tree in pre-order and yields one entry per node, paired
  /// with the path that reaches it. The first entry is always the root
  /// with an empty path. Used by the round-trip property test to
  /// enumerate edit targets.
  List<({NodePath path, WidgetNode node})> walk() {
    final out = <({NodePath path, WidgetNode node})>[];
    _walk(root, const <NodePathSegment>[], out);
    return out;
  }
}

WidgetNode? _nodeAt(WidgetNode start, NodePath path) {
  var current = start;
  for (final segment in path) {
    final slot = current.childSlots[segment.slot];
    if (slot == null || segment.index < 0 || segment.index >= slot.length) {
      return null;
    }
    current = slot[segment.index];
  }
  return current;
}

WidgetNode _withProperty(
  WidgetNode node,
  NodePath path,
  String propName,
  PropertyValue value,
) {
  if (path.isEmpty) {
    if (!node.properties.containsKey(propName)) {
      throw ArgumentError(
        '${node.className} has no property "$propName" to update',
      );
    }
    final newProps = <String, PropertyValue>{
      ...node.properties,
      propName: value,
    };
    return WidgetNode(
      className: node.className,
      properties: newProps,
      childSlots: node.childSlots,
      sourceSpan: node.sourceSpan,
      styleHints: node.styleHints,
    );
  }
  final segment = path.first;
  final rest = path.sublist(1);
  final slot = node.childSlots[segment.slot];
  if (slot == null) {
    throw ArgumentError(
      '${node.className} has no slot "${segment.slot}"',
    );
  }
  if (segment.index < 0 || segment.index >= slot.length) {
    throw ArgumentError(
      'Index ${segment.index} out of range for ${node.className}.${segment.slot} (length ${slot.length})',
    );
  }
  final updatedChild = _withProperty(
    slot[segment.index],
    rest,
    propName,
    value,
  );
  final updatedSlot = <WidgetNode>[
    ...slot.sublist(0, segment.index),
    updatedChild,
    ...slot.sublist(segment.index + 1),
  ];
  final newSlots = <String, List<WidgetNode>>{
    ...node.childSlots,
    segment.slot: updatedSlot,
  };
  return WidgetNode(
    className: node.className,
    properties: node.properties,
    childSlots: newSlots,
    sourceSpan: node.sourceSpan,
    styleHints: node.styleHints,
  );
}

void _walk(
  WidgetNode node,
  NodePath pathSoFar,
  List<({NodePath path, WidgetNode node})> out,
) {
  out.add((path: pathSoFar, node: node));
  for (final slotEntry in node.childSlots.entries) {
    for (var i = 0; i < slotEntry.value.length; i++) {
      final segment = (slot: slotEntry.key, index: i);
      _walk(slotEntry.value[i], [...pathSoFar, segment], out);
    }
  }
}
