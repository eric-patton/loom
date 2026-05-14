import 'property_value.dart';
import 'widget_node.dart';

/// One step along a path through the model: which child slot to descend
/// into, and which index within that slot.
///
/// `MethodReferenceNode` is navigated through a virtual slot named
/// `body` with index `0` — paths that descend into a helper method's
/// resolved widget tree include such a segment.
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

const String _methodBodySlot = 'body';

extension NodeNavigation on WidgetTreeModel {
  /// Returns the node reached by following `path`, or `null` if the path
  /// is invalid. The result may be a `WidgetNode`, an `OpaqueNode`, or a
  /// `MethodReferenceNode`.
  ModelNode? nodeAt(NodePath path) => _nodeAt(root, path);

  /// Returns a new model with the property at `path / propName` replaced
  /// by `value`. Throws `OpaqueEditException` if `path` descends into an
  /// `OpaqueNode`; throws `ArgumentError` if the target node doesn't have
  /// a property with the given name.
  WidgetTreeModel withProperty(
    NodePath path,
    String propName,
    PropertyValue value,
  ) =>
      WidgetTreeModel(root: _withProperty(root, path, propName, value));

  /// Returns a new model with `newChild` inserted at `parentPath / slot`
  /// at the given `index`. Throws `ArgumentError` if the slot is not
  /// list-shaped (see `_requireListSlotParent`).
  WidgetTreeModel insertChild(
    NodePath parentPath,
    String slot,
    int index,
    ModelNode newChild,
  ) {
    _requireListSlotParent(parentPath, slot);
    return WidgetTreeModel(
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
  }

  /// Returns a new model with the child at `parentPath / slot[index]`
  /// removed. Throws `ArgumentError` if the slot is not list-shaped.
  WidgetTreeModel removeChild(NodePath parentPath, String slot, int index) {
    _requireListSlotParent(parentPath, slot);
    return WidgetTreeModel(
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
  }

  /// Returns a new model with the child at `parentPath / slot[from]`
  /// moved to position `to`. Throws `ArgumentError` if the slot is not
  /// list-shaped.
  WidgetTreeModel moveChild(
    NodePath parentPath,
    String slot,
    int from,
    int to,
  ) {
    _requireListSlotParent(parentPath, slot);
    return WidgetTreeModel(
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
  }

  /// Guards `insertChild` / `removeChild` / `moveChild`: the model-level
  /// structural-edit API operates only on list-shaped slots (those with
  /// a captured `ListSlotStyle`). Single-shaped slots (e.g. `child:`)
  /// and slots whose source expression isn't a list literal (e.g.
  /// `children: spread()`, which the visitor captures as a single
  /// `OpaqueNode` with no `ListSlotStyle`) are rejected here so the
  /// model and `EditPlanner` agree on what's editable — otherwise the
  /// model would accept a mutation that the planner refuses to
  /// serialize back to source.
  void _requireListSlotParent(NodePath parentPath, String slot) {
    final node = nodeAt(parentPath);
    if (node == null) {
      throw ArgumentError('parentPath does not resolve to any node');
    }
    if (node is! WidgetNode) {
      throw ArgumentError(
        'parentPath resolves to ${node.runtimeType}, not a WidgetNode',
      );
    }
    if (!node.childSlotStyles.containsKey(slot)) {
      throw ArgumentError(
        '${node.className}.$slot is not a list-shaped slot; '
        'structural edits require a list-shaped slot. Single-shaped '
        'slots and slots whose source expression is not a list literal '
        '(e.g. children: spread()) cannot be structurally edited.',
      );
    }
  }

  /// Walks the tree in pre-order and yields one entry per node, paired
  /// with the path that reaches it. Descends through `WidgetNode`'s
  /// child slots and through `MethodReferenceNode`'s virtual `body` slot.
  /// `OpaqueNode`s are leaves.
  List<({NodePath path, ModelNode node})> walk() {
    final out = <({NodePath path, ModelNode node})>[];
    _walk(root, const <NodePathSegment>[], out);
    return out;
  }
}

ModelNode? _nodeAt(ModelNode start, NodePath path) {
  ModelNode current = start;
  for (final segment in path) {
    if (current is WidgetNode) {
      final slot = current.childSlots[segment.slot];
      if (slot == null || segment.index < 0 || segment.index >= slot.length) {
        return null;
      }
      current = slot[segment.index];
    } else if (current is MethodReferenceNode) {
      if (segment.slot != _methodBodySlot || segment.index != 0) {
        return null;
      }
      current = current.body;
    } else {
      // OpaqueNode: cannot descend.
      return null;
    }
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
  final newChild = _withPropertyOnModelNode(
    descendingInto,
    rest,
    propName,
    value,
  );
  final updatedSlot = <ModelNode>[
    ...slot.sublist(0, segment.index),
    newChild,
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

ModelNode _withPropertyOnModelNode(
  ModelNode node,
  NodePath path,
  String propName,
  PropertyValue value,
) {
  switch (node) {
    case final WidgetNode w:
      return _withProperty(w, path, propName, value);
    case final MethodReferenceNode m:
      if (path.isEmpty) {
        // Can't set a property directly on a MethodReferenceNode — its
        // "properties" live inside the body. Caller's path probably
        // expected to descend further.
        throw ArgumentError(
          'MethodReferenceNode has no editable properties at this position; '
          'descend into "body" first.',
        );
      }
      final segment = path.first;
      if (segment.slot != _methodBodySlot || segment.index != 0) {
        throw ArgumentError(
          'Only the virtual "body" slot (index 0) is valid for '
          'MethodReferenceNode; got "${segment.slot}[${segment.index}]"',
        );
      }
      final newBody = _withPropertyOnModelNode(
        m.body,
        path.sublist(1),
        propName,
        value,
      );
      return MethodReferenceNode(
        methodName: m.methodName,
        callSourceSpan: m.callSourceSpan,
        body: newBody,
      );
    case OpaqueNode():
      throw const OpaqueEditException(
        'path descends into an OpaqueNode; opaque content is not editable',
      );
  }
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
  final updatedChild = _modifySlotOnModelNode(
    descendingInto,
    rest,
    slotName,
    transform,
  );
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

ModelNode _modifySlotOnModelNode(
  ModelNode node,
  NodePath path,
  String slotName,
  List<ModelNode> Function(List<ModelNode> current) transform,
) {
  switch (node) {
    case final WidgetNode w:
      return _modifySlot(w, path, slotName, transform);
    case final MethodReferenceNode m:
      if (path.isEmpty) {
        throw ArgumentError(
          'MethodReferenceNode has no editable slots at this position; '
          'descend into "body" first.',
        );
      }
      final segment = path.first;
      if (segment.slot != _methodBodySlot || segment.index != 0) {
        throw ArgumentError(
          'Only the virtual "body" slot (index 0) is valid for '
          'MethodReferenceNode; got "${segment.slot}[${segment.index}]"',
        );
      }
      final newBody = _modifySlotOnModelNode(
        m.body,
        path.sublist(1),
        slotName,
        transform,
      );
      return MethodReferenceNode(
        methodName: m.methodName,
        callSourceSpan: m.callSourceSpan,
        body: newBody,
      );
    case OpaqueNode():
      throw const OpaqueEditException(
        'path descends into an OpaqueNode; opaque content is not editable',
      );
  }
}

void _walk(
  ModelNode node,
  NodePath pathSoFar,
  List<({NodePath path, ModelNode node})> out,
) {
  out.add((path: pathSoFar, node: node));
  switch (node) {
    case final WidgetNode w:
      for (final slotEntry in w.childSlots.entries) {
        for (var i = 0; i < slotEntry.value.length; i++) {
          final segment = (slot: slotEntry.key, index: i);
          _walk(slotEntry.value[i], [...pathSoFar, segment], out);
        }
      }
    case final MethodReferenceNode m:
      const segment = (slot: _methodBodySlot, index: 0);
      _walk(m.body, [...pathSoFar, segment], out);
    case OpaqueNode():
      // Leaf.
      break;
  }
}
