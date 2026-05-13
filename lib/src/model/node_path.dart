import 'property_value.dart';
import 'widget_node.dart';

/// One step along a path through the model: which child slot to descend
/// into, and which index within that slot.
typedef NodePathSegment = ({String slot, int index});

/// A path from the model's root to a specific node, expressed as a
/// sequence of (slot, index) descents. The empty list points at the root.
typedef NodePath = List<NodePathSegment>;

/// Thrown when a model edit tries to descend into or mutate an
/// `OpaqueNode`. Opaque content is byte-preserved by contract.
class OpaqueEditException implements Exception {
  const OpaqueEditException(this.message);
  final String message;
  @override
  String toString() => 'OpaqueEditException: $message';
}

extension NodeNavigation on WidgetTreeModel {
  /// Returns the node reached by following `path`, or `null` if the path
  /// is invalid (unknown slot or out-of-range index). The result may be
  /// either a `WidgetNode` or an `OpaqueNode`.
  ModelNode? nodeAt(NodePath path) => _nodeAt(root, path);

  /// Returns a new model with the property at `path / propName` replaced
  /// by `value`. Other parts of the tree are structurally unchanged
  /// (and physically reused where possible since `WidgetNode` is immutable).
  ///
  /// Throws `OpaqueEditException` if `path` descends into an `OpaqueNode`,
  /// or `ArgumentError` if `path` ends on a node that doesn't have a
  /// property with the given name.
  WidgetTreeModel withProperty(
    NodePath path,
    String propName,
    PropertyValue value,
  ) =>
      WidgetTreeModel(root: _withProperty(root, path, propName, value));

  /// Returns a new model with `newChild` inserted at `parentPath / slot`
  /// at the given `index`. The slot must exist and be list-shaped.
  /// Indices in `[0, slot.length]` are valid; `slot.length` appends.
  /// Throws `OpaqueEditException` if `parentPath` descends into an
  /// `OpaqueNode`.
  WidgetTreeModel insertChild(
    NodePath parentPath,
    String slot,
    int index,
    ModelNode newChild,
  ) =>
      WidgetTreeModel(
        root: _modifySlot(root, parentPath, slot, (current) {
          if (index < 0 || index > current.length) {
            throw ArgumentError(
              'Insert index $index out of range [0, ${current.length}]',
            );
          }
          return <ModelNode>[
            ...current.sublist(0, index),
            newChild,
            ...current.sublist(index),
          ];
        }),
      );

  /// Returns a new model with the child at `parentPath / slot[index]`
  /// removed. The removed entry may be a `WidgetNode` or `OpaqueNode` —
  /// removal moves it as a unit either way.
  WidgetTreeModel removeChild(NodePath parentPath, String slot, int index) =>
      WidgetTreeModel(
        root: _modifySlot(root, parentPath, slot, (current) {
          if (index < 0 || index >= current.length) {
            throw ArgumentError(
              'Remove index $index out of range [0, ${current.length})',
            );
          }
          return <ModelNode>[
            ...current.sublist(0, index),
            ...current.sublist(index + 1),
          ];
        }),
      );

  /// Returns a new model with the child at `parentPath / slot[from]`
  /// moved to position `to`. Works on either widget or opaque entries.
  WidgetTreeModel moveChild(
    NodePath parentPath,
    String slot,
    int from,
    int to,
  ) =>
      WidgetTreeModel(
        root: _modifySlot(root, parentPath, slot, (current) {
          if (from < 0 || from >= current.length) {
            throw ArgumentError(
              'Move source $from out of range [0, ${current.length})',
            );
          }
          if (to < 0 || to >= current.length) {
            throw ArgumentError(
              'Move destination $to out of range [0, ${current.length})',
            );
          }
          if (from == to) {
            return current;
          }
          final mutable = <ModelNode>[...current];
          final moved = mutable.removeAt(from);
          mutable.insert(to, moved);
          return mutable;
        }),
      );

  /// Walks the tree in pre-order and yields one entry per node, paired
  /// with the path that reaches it. Includes both `WidgetNode`s and
  /// `OpaqueNode`s. The first entry is always the root with an empty path.
  List<({NodePath path, ModelNode node})> walk() {
    final out = <({NodePath path, ModelNode node})>[];
    _walk(root, const <NodePathSegment>[], out);
    return out;
  }
}

ModelNode? _nodeAt(ModelNode start, NodePath path) {
  ModelNode current = start;
  for (final segment in path) {
    if (current is! WidgetNode) {
      // Can't descend into opaque (no childSlots).
      return null;
    }
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
      childSlotStyles: node.childSlotStyles,
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
  final descendingInto = slot[segment.index];
  if (descendingInto is! WidgetNode) {
    throw const OpaqueEditException(
      'path descends into an OpaqueNode; opaque content is not editable',
    );
  }
  final updatedChild = _withProperty(descendingInto, rest, propName, value);
  final updatedSlot = <ModelNode>[
    ...slot.sublist(0, segment.index),
    updatedChild,
    ...slot.sublist(segment.index + 1),
  ];
  final newSlots = <String, List<ModelNode>>{
    ...node.childSlots,
    segment.slot: updatedSlot,
  };
  return WidgetNode(
    className: node.className,
    properties: node.properties,
    childSlots: newSlots,
    childSlotStyles: node.childSlotStyles,
    sourceSpan: node.sourceSpan,
    styleHints: node.styleHints,
  );
}

WidgetNode _modifySlot(
  WidgetNode node,
  NodePath path,
  String slotName,
  List<ModelNode> Function(List<ModelNode> current) transform,
) {
  if (path.isEmpty) {
    final current = node.childSlots[slotName];
    if (current == null) {
      throw ArgumentError(
        '${node.className} has no slot "$slotName"',
      );
    }
    final updated = transform(current);
    final newSlots = <String, List<ModelNode>>{
      ...node.childSlots,
      slotName: updated,
    };
    return WidgetNode(
      className: node.className,
      properties: node.properties,
      childSlots: newSlots,
      childSlotStyles: node.childSlotStyles,
      sourceSpan: node.sourceSpan,
      styleHints: node.styleHints,
    );
  }
  final segment = path.first;
  final rest = path.sublist(1);
  final descend = node.childSlots[segment.slot];
  if (descend == null) {
    throw ArgumentError(
      '${node.className} has no slot "${segment.slot}"',
    );
  }
  if (segment.index < 0 || segment.index >= descend.length) {
    throw ArgumentError(
      'Index ${segment.index} out of range for ${node.className}.${segment.slot}',
    );
  }
  final descendingInto = descend[segment.index];
  if (descendingInto is! WidgetNode) {
    throw const OpaqueEditException(
      'path descends into an OpaqueNode; opaque content is not editable',
    );
  }
  final updatedChild = _modifySlot(descendingInto, rest, slotName, transform);
  final updatedSlot = <ModelNode>[
    ...descend.sublist(0, segment.index),
    updatedChild,
    ...descend.sublist(segment.index + 1),
  ];
  final newSlots = <String, List<ModelNode>>{
    ...node.childSlots,
    segment.slot: updatedSlot,
  };
  return WidgetNode(
    className: node.className,
    properties: node.properties,
    childSlots: newSlots,
    childSlotStyles: node.childSlotStyles,
    sourceSpan: node.sourceSpan,
    styleHints: node.styleHints,
  );
}

void _walk(
  ModelNode node,
  NodePath pathSoFar,
  List<({NodePath path, ModelNode node})> out,
) {
  out.add((path: pathSoFar, node: node));
  if (node is WidgetNode) {
    for (final slotEntry in node.childSlots.entries) {
      for (var i = 0; i < slotEntry.value.length; i++) {
        final segment = (slot: slotEntry.key, index: i);
        _walk(slotEntry.value[i], [...pathSoFar, segment], out);
      }
    }
  }
}
