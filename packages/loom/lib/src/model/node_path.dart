import 'list_slot_style.dart';
import 'node.dart';
import 'property_value.dart';
import 'source_span.dart';
import 'style_hints.dart';

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
      WidgetTreeModel(
        root: _withPropertyOnModelNode(root, path, propName, value),
        diagnostics: diagnostics,
      );

  /// Returns a new model with `newChild` inserted at `parentPath / slot`
  /// at the given `index`. Throws `ArgumentError` if the slot is not
  /// list-shaped (see `_requireListSlotParent`).
  WidgetTreeModel insertChild(
    NodePath parentPath,
    String slot,
    int index,
    ModelNode newChild,
  ) {
    _requireListSlotParent(root, parentPath, slot);
    return WidgetTreeModel(
      root: _modifySlotOnModelNode(root, parentPath, slot, (current) {
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
      diagnostics: diagnostics,
    );
  }

  /// Returns a new model with the child at `parentPath / slot[index]`
  /// removed. Throws `ArgumentError` if the slot is not list-shaped.
  WidgetTreeModel removeChild(NodePath parentPath, String slot, int index) {
    _requireListSlotParent(root, parentPath, slot);
    return WidgetTreeModel(
      root: _modifySlotOnModelNode(root, parentPath, slot, (current) {
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
      diagnostics: diagnostics,
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
    _requireListSlotParent(root, parentPath, slot);
    return WidgetTreeModel(
      root: _modifySlotOnModelNode(root, parentPath, slot, (current) {
        return _moveInList(current, from, to);
      }),
      diagnostics: diagnostics,
    );
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

/// Same surface as `NodeNavigation` (above) but for `RouteTreeModel`.
///
/// `RouteNode`, `WidgetNode`, and `PipelineNode` share the same
/// constructor-call shape (className + namedConstructor + properties +
/// childSlots + styleHints), so the underlying helpers operate uniformly
/// on any of the three; only the wrapping model type and the leading
/// type-guard differ.
extension RouteTreeNavigation on RouteTreeModel {
  ModelNode? nodeAt(NodePath path) => _nodeAt(root, path);

  RouteTreeModel withProperty(
    NodePath path,
    String propName,
    PropertyValue value,
  ) =>
      RouteTreeModel(
        root: _withPropertyOnModelNode(root, path, propName, value),
        diagnostics: diagnostics,
      );

  RouteTreeModel insertChild(
    NodePath parentPath,
    String slot,
    int index,
    ModelNode newChild,
  ) {
    _requireListSlotParent(root, parentPath, slot);
    return RouteTreeModel(
      root: _modifySlotOnModelNode(root, parentPath, slot, (current) {
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
      diagnostics: diagnostics,
    );
  }

  RouteTreeModel removeChild(NodePath parentPath, String slot, int index) {
    _requireListSlotParent(root, parentPath, slot);
    return RouteTreeModel(
      root: _modifySlotOnModelNode(root, parentPath, slot, (current) {
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
      diagnostics: diagnostics,
    );
  }

  RouteTreeModel moveChild(
    NodePath parentPath,
    String slot,
    int from,
    int to,
  ) {
    _requireListSlotParent(root, parentPath, slot);
    return RouteTreeModel(
      root: _modifySlotOnModelNode(root, parentPath, slot, (current) {
        return _moveInList(current, from, to);
      }),
      diagnostics: diagnostics,
    );
  }

  List<({NodePath path, ModelNode node})> walk() {
    final out = <({NodePath path, ModelNode node})>[];
    _walk(root, const <NodePathSegment>[], out);
    return out;
  }
}

/// Same surface as `NodeNavigation`, for `PipelineTreeModel`.
extension PipelineTreeNavigation on PipelineTreeModel {
  ModelNode? nodeAt(NodePath path) => _nodeAt(root, path);

  PipelineTreeModel withProperty(
    NodePath path,
    String propName,
    PropertyValue value,
  ) =>
      PipelineTreeModel(
        root: _withPropertyOnModelNode(root, path, propName, value),
        diagnostics: diagnostics,
      );

  PipelineTreeModel insertChild(
    NodePath parentPath,
    String slot,
    int index,
    ModelNode newChild,
  ) {
    _requireListSlotParent(root, parentPath, slot);
    return PipelineTreeModel(
      root: _modifySlotOnModelNode(root, parentPath, slot, (current) {
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
      diagnostics: diagnostics,
    );
  }

  PipelineTreeModel removeChild(NodePath parentPath, String slot, int index) {
    _requireListSlotParent(root, parentPath, slot);
    return PipelineTreeModel(
      root: _modifySlotOnModelNode(root, parentPath, slot, (current) {
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
      diagnostics: diagnostics,
    );
  }

  PipelineTreeModel moveChild(
    NodePath parentPath,
    String slot,
    int from,
    int to,
  ) {
    _requireListSlotParent(root, parentPath, slot);
    return PipelineTreeModel(
      root: _modifySlotOnModelNode(root, parentPath, slot, (current) {
        return _moveInList(current, from, to);
      }),
      diagnostics: diagnostics,
    );
  }

  List<({NodePath path, ModelNode node})> walk() {
    final out = <({NodePath path, ModelNode node})>[];
    _walk(root, const <NodePathSegment>[], out);
    return out;
  }
}

/// Read-only view of the fields shared by every constructor-call node
/// (`WidgetNode`, `RouteNode`, `PipelineNode`). Used by the navigation
/// helpers to walk/rebuild without caring which concrete type they have.
class _CallView {
  _CallView({
    required this.className,
    required this.namedConstructor,
    required this.properties,
    required this.childSlots,
    required this.childSlotStyles,
    required this.sourceSpan,
    required this.styleHints,
  });

  final String className;
  final String? namedConstructor;
  final Map<String, PropertyValue> properties;
  final Map<String, List<ModelNode>> childSlots;
  final Map<String, ListSlotStyle> childSlotStyles;
  final SourceSpan sourceSpan;
  final StyleHints styleHints;
}

_CallView? _viewOf(ModelNode node) => switch (node) {
      final WidgetNode w => _CallView(
          className: w.className,
          namedConstructor: w.namedConstructor,
          properties: w.properties,
          childSlots: w.childSlots,
          childSlotStyles: w.childSlotStyles,
          sourceSpan: w.sourceSpan,
          styleHints: w.styleHints,
        ),
      final RouteNode r => _CallView(
          className: r.className,
          namedConstructor: r.namedConstructor,
          properties: r.properties,
          childSlots: r.childSlots,
          childSlotStyles: r.childSlotStyles,
          sourceSpan: r.sourceSpan,
          styleHints: r.styleHints,
        ),
      final PipelineNode p => _CallView(
          className: p.className,
          namedConstructor: p.namedConstructor,
          properties: p.properties,
          childSlots: p.childSlots,
          childSlotStyles: p.childSlotStyles,
          sourceSpan: p.sourceSpan,
          styleHints: p.styleHints,
        ),
      _ => null,
    };

/// Rebuilds a constructor-call node, preserving its concrete subtype
/// (so a `RouteNode` parent stays a `RouteNode` after a child edit).
ModelNode _rebuildCall(
  ModelNode original, {
  required Map<String, PropertyValue> properties,
  required Map<String, List<ModelNode>> childSlots,
}) {
  return switch (original) {
    final WidgetNode w => WidgetNode(
        className: w.className,
        namedConstructor: w.namedConstructor,
        properties: properties,
        childSlots: childSlots,
        childSlotStyles: w.childSlotStyles,
        sourceSpan: w.sourceSpan,
        styleHints: w.styleHints,
      ),
    final RouteNode r => RouteNode(
        className: r.className,
        namedConstructor: r.namedConstructor,
        properties: properties,
        childSlots: childSlots,
        childSlotStyles: r.childSlotStyles,
        sourceSpan: r.sourceSpan,
        styleHints: r.styleHints,
      ),
    final PipelineNode p => PipelineNode(
        className: p.className,
        namedConstructor: p.namedConstructor,
        properties: properties,
        childSlots: childSlots,
        childSlotStyles: p.childSlotStyles,
        sourceSpan: p.sourceSpan,
        styleHints: p.styleHints,
      ),
    _ => throw StateError(
        'Not a constructor-call node: ${original.runtimeType}',
      ),
  };
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
void _requireListSlotParent(ModelNode root, NodePath parentPath, String slot) {
  final node = _nodeAt(root, parentPath);
  if (node == null) {
    throw ArgumentError('parentPath does not resolve to any node');
  }
  final view = _viewOf(node);
  if (view == null) {
    throw ArgumentError(
      'parentPath resolves to ${node.runtimeType}, not a '
      'constructor-call node (WidgetNode/RouteNode/PipelineNode)',
    );
  }
  if (!view.childSlotStyles.containsKey(slot)) {
    throw ArgumentError(
      '${view.className}.$slot is not a list-shaped slot; '
      'structural edits require a list-shaped slot. Single-shaped '
      'slots and slots whose source expression is not a list literal '
      '(e.g. children: spread()) cannot be structurally edited.',
    );
  }
}

List<ModelNode> _moveInList(List<ModelNode> current, int from, int to) {
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
  if (from == to) return current;
  final mutable = <ModelNode>[...current];
  final moved = mutable.removeAt(from);
  mutable.insert(to, moved);
  return mutable;
}

ModelNode? _nodeAt(ModelNode start, NodePath path) {
  ModelNode current = start;
  for (final segment in path) {
    final view = _viewOf(current);
    if (view != null) {
      final slot = view.childSlots[segment.slot];
      if (slot == null || segment.index < 0 || segment.index >= slot.length) {
        return null;
      }
      current = slot[segment.index];
      continue;
    }
    if (current is MethodReferenceNode) {
      if (segment.slot != _methodBodySlot || segment.index != 0) {
        return null;
      }
      current = current.body;
      continue;
    }
    // OpaqueNode: cannot descend.
    return null;
  }
  return current;
}

ModelNode _withCallProperty(
  ModelNode node,
  NodePath path,
  String propName,
  PropertyValue value,
) {
  final view = _viewOf(node);
  if (view == null) {
    throw StateError('not a constructor-call node: ${node.runtimeType}');
  }
  if (path.isEmpty) {
    if (!view.properties.containsKey(propName)) {
      throw ArgumentError(
        '${view.className} has no property "$propName" to update',
      );
    }
    final newProps = <String, PropertyValue>{
      ...view.properties,
      propName: value,
    };
    return _rebuildCall(node,
        properties: newProps, childSlots: view.childSlots);
  }
  final segment = path.first;
  final rest = path.sublist(1);
  final slot = view.childSlots[segment.slot];
  if (slot == null) {
    throw ArgumentError(
      '${view.className} has no slot "${segment.slot}"',
    );
  }
  if (segment.index < 0 || segment.index >= slot.length) {
    throw ArgumentError(
      'Index ${segment.index} out of range for ${view.className}.${segment.slot} (length ${slot.length})',
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
    ...view.childSlots,
    segment.slot: updatedSlot,
  };
  return _rebuildCall(node, properties: view.properties, childSlots: newSlots);
}

ModelNode _withPropertyOnModelNode(
  ModelNode node,
  NodePath path,
  String propName,
  PropertyValue value,
) {
  if (_viewOf(node) != null) {
    return _withCallProperty(node, path, propName, value);
  }
  switch (node) {
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
    case WidgetNode():
    case RouteNode():
    case PipelineNode():
      // Already handled by the _viewOf check above; the analyzer
      // doesn't statically know that, so this branch is unreachable
      // but required for exhaustive switch on `ModelNode`.
      throw StateError('unreachable: view-bearing case');
  }
}

ModelNode _modifyCallSlot(
  ModelNode node,
  NodePath path,
  String slotName,
  List<ModelNode> Function(List<ModelNode> current) transform,
) {
  final view = _viewOf(node);
  if (view == null) {
    throw StateError('not a constructor-call node: ${node.runtimeType}');
  }
  if (path.isEmpty) {
    final current = view.childSlots[slotName];
    if (current == null) {
      throw ArgumentError(
        '${view.className} has no slot "$slotName"',
      );
    }
    final updated = transform(current);
    final newSlots = <String, List<ModelNode>>{
      ...view.childSlots,
      slotName: updated,
    };
    return _rebuildCall(
      node,
      properties: view.properties,
      childSlots: newSlots,
    );
  }
  final segment = path.first;
  final rest = path.sublist(1);
  final descend = view.childSlots[segment.slot];
  if (descend == null) {
    throw ArgumentError(
      '${view.className} has no slot "${segment.slot}"',
    );
  }
  if (segment.index < 0 || segment.index >= descend.length) {
    throw ArgumentError(
      'Index ${segment.index} out of range for ${view.className}.${segment.slot}',
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
    ...view.childSlots,
    segment.slot: updatedSlot,
  };
  return _rebuildCall(node, properties: view.properties, childSlots: newSlots);
}

ModelNode _modifySlotOnModelNode(
  ModelNode node,
  NodePath path,
  String slotName,
  List<ModelNode> Function(List<ModelNode> current) transform,
) {
  if (_viewOf(node) != null) {
    return _modifyCallSlot(node, path, slotName, transform);
  }
  switch (node) {
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
    case WidgetNode():
    case RouteNode():
    case PipelineNode():
      throw StateError('unreachable: view-bearing case');
  }
}

void _walk(
  ModelNode node,
  NodePath pathSoFar,
  List<({NodePath path, ModelNode node})> out,
) {
  out.add((path: pathSoFar, node: node));
  final view = _viewOf(node);
  if (view != null) {
    for (final slotEntry in view.childSlots.entries) {
      for (var i = 0; i < slotEntry.value.length; i++) {
        final segment = (slot: slotEntry.key, index: i);
        _walk(slotEntry.value[i], [...pathSoFar, segment], out);
      }
    }
    return;
  }
  switch (node) {
    case final MethodReferenceNode m:
      const segment = (slot: _methodBodySlot, index: 0);
      _walk(m.body, [...pathSoFar, segment], out);
    case OpaqueNode():
      // Leaf.
      break;
    case WidgetNode():
    case RouteNode():
    case PipelineNode():
      // Already covered by the _viewOf check above.
      break;
  }
}
