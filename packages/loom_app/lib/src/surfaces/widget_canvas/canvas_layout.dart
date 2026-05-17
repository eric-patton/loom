import 'dart:ui';

import '../../services/kernel_adapter.dart';
import 'canvas_rect.dart';

/// Result of laying out a widget tree onto a flat canvas. Holds the
/// rectangle list (pre-order, parents before children) and a deepest-
/// match hit-test API. Recreation, not preview — the geometry mimics
/// how the live tree might compose without ever running user code.
class CanvasLayout {
  CanvasLayout(this.rects);

  final List<CanvasRect> rects;

  /// Returns the deepest rectangle containing [point], or null when no
  /// rectangle contains it. Pre-order means later entries are always
  /// deeper, so the last container wins.
  CanvasRect? hitTest(Offset point) {
    CanvasRect? best;
    for (final r in rects) {
      if (r.rect.contains(point)) best = r;
    }
    return best;
  }
}

/// Layout entry point. Walks [model] and produces one [CanvasRect] per
/// node, fitted into [canvasRect]. When the available area degenerates
/// below [_kMinRectWidth] × [_kMinRectHeight] the algorithm stops
/// descending — the parent still paints, but its children are
/// dropped from the layout (they remain reachable via the outline
/// pane).
CanvasLayout layoutTree(WidgetTreeModel model, Rect canvasRect) {
  final out = <CanvasRect>[];
  _layoutNode(
    node: model.root,
    path: const <NodePathSegment>[],
    rect: canvasRect,
    out: out,
  );
  return CanvasLayout(out);
}

const double _kLabelHeight = 20;
const double _kInset = 4;
const double _kMinRectWidth = 40;
const double _kMinRectHeight = 28;
const double _kChildGap = 2;

/// Inner area available to children, given a parent rectangle. Strips
/// off the label band at the top and a small inset on the other three
/// sides.
Rect childrenAreaOf(Rect parent) {
  final raw = Rect.fromLTRB(
    parent.left + _kInset,
    parent.top + _kLabelHeight,
    parent.right - _kInset,
    parent.bottom - _kInset,
  );
  if (raw.width <= 0 || raw.height <= 0) return Rect.zero;
  return raw;
}

void _layoutNode({
  required ModelNode node,
  required NodePath path,
  required Rect rect,
  required List<CanvasRect> out,
}) {
  out.add(CanvasRect(path: path, rect: rect, node: node));
  if (node is! WidgetNode) return;
  final inner = childrenAreaOf(rect);
  if (inner.width < _kMinRectWidth || inner.height < _kMinRectHeight) return;
  _layoutChildren(node, inner, path, out);
}

void _layoutChildren(
  WidgetNode parent,
  Rect inner,
  NodePath parentPath,
  List<CanvasRect> out,
) {
  if (parent.className == 'Scaffold') {
    _layoutScaffoldSlots(parent, inner, parentPath, out);
    return;
  }
  final mode = _modeFor(parent);
  // Flatten slots into [(segment, child)] in slot-declaration order.
  final flat = <(NodePathSegment, ModelNode)>[
    for (final slot in parent.childSlots.entries)
      for (var i = 0; i < slot.value.length; i++)
        ((slot: slot.key, index: i), slot.value[i]),
  ];
  if (flat.isEmpty) return;
  switch (mode) {
    case _LayoutMode.horizontal:
      _splitAxis(flat, inner, parentPath, out, horizontal: true);
    case _LayoutMode.vertical:
      _splitAxis(flat, inner, parentPath, out, horizontal: false);
    case _LayoutMode.overlay:
      for (final (seg, child) in flat) {
        _layoutNode(
          node: child,
          path: <NodePathSegment>[...parentPath, seg],
          rect: inner,
          out: out,
        );
      }
    case _LayoutMode.inset:
      _layoutNode(
        node: flat.first.$2,
        path: <NodePathSegment>[...parentPath, flat.first.$1],
        rect: inner,
        out: out,
      );
  }
}

void _splitAxis(
  List<(NodePathSegment, ModelNode)> children,
  Rect inner,
  NodePath parentPath,
  List<CanvasRect> out, {
  required bool horizontal,
}) {
  final n = children.length;
  final total = horizontal ? inner.width : inner.height;
  final gapTotal = (n - 1) * _kChildGap;
  final per = (total - gapTotal) / n;
  if (per <= 0) return;
  for (var i = 0; i < n; i++) {
    final (seg, child) = children[i];
    final start = i * (per + _kChildGap);
    final Rect childRect;
    if (horizontal) {
      childRect = Rect.fromLTWH(
        inner.left + start,
        inner.top,
        per,
        inner.height,
      );
    } else {
      childRect = Rect.fromLTWH(
        inner.left,
        inner.top + start,
        inner.width,
        per,
      );
    }
    _layoutNode(
      node: child,
      path: <NodePathSegment>[...parentPath, seg],
      rect: childRect,
      out: out,
    );
  }
}

/// Specialized layout for `Scaffold`: appBar pins to the top, bottom
/// nav to the bottom, the body fills what remains, the FAB overlays
/// the bottom-right. Other slots (drawer, endDrawer, persistentFooter,
/// bottomSheet) fall back to occupying the remaining body area
/// stacked vertically.
void _layoutScaffoldSlots(
  WidgetNode scaffold,
  Rect inner,
  NodePath parentPath,
  List<CanvasRect> out,
) {
  const double appBarHeight = 32;
  const double bottomBarHeight = 40;
  const double fabSize = 36;

  var bodyRect = inner;
  final slots = scaffold.childSlots;

  final appBarChildren = slots['appBar'] ?? const <ModelNode>[];
  if (appBarChildren.isNotEmpty) {
    final rect = Rect.fromLTWH(
      inner.left,
      inner.top,
      inner.width,
      appBarHeight,
    );
    _placeSlotChildren(
      children: appBarChildren,
      slotName: 'appBar',
      rect: rect,
      parentPath: parentPath,
      out: out,
      horizontal: true,
    );
    bodyRect = Rect.fromLTRB(
      bodyRect.left,
      bodyRect.top + appBarHeight + _kChildGap,
      bodyRect.right,
      bodyRect.bottom,
    );
  }

  final bottomChildren = slots['bottomNavigationBar'] ?? const <ModelNode>[];
  if (bottomChildren.isNotEmpty) {
    final rect = Rect.fromLTWH(
      inner.left,
      inner.bottom - bottomBarHeight,
      inner.width,
      bottomBarHeight,
    );
    _placeSlotChildren(
      children: bottomChildren,
      slotName: 'bottomNavigationBar',
      rect: rect,
      parentPath: parentPath,
      out: out,
      horizontal: true,
    );
    bodyRect = Rect.fromLTRB(
      bodyRect.left,
      bodyRect.top,
      bodyRect.right,
      bodyRect.bottom - bottomBarHeight - _kChildGap,
    );
  }

  final bodyChildren = slots['body'] ?? const <ModelNode>[];
  if (bodyChildren.isNotEmpty && bodyRect.width > 0 && bodyRect.height > 0) {
    if (bodyChildren.length == 1) {
      _layoutNode(
        node: bodyChildren.first,
        path: <NodePathSegment>[...parentPath, (slot: 'body', index: 0)],
        rect: bodyRect,
        out: out,
      );
    } else {
      _placeSlotChildren(
        children: bodyChildren,
        slotName: 'body',
        rect: bodyRect,
        parentPath: parentPath,
        out: out,
        horizontal: false,
      );
    }
  }

  final fabChildren = slots['floatingActionButton'] ?? const <ModelNode>[];
  if (fabChildren.isNotEmpty) {
    final rect = Rect.fromLTWH(
      inner.right - fabSize - 4,
      inner.bottom -
          fabSize -
          (bottomChildren.isNotEmpty ? bottomBarHeight + 4 : 4),
      fabSize,
      fabSize,
    );
    for (var i = 0; i < fabChildren.length; i++) {
      _layoutNode(
        node: fabChildren[i],
        path: <NodePathSegment>[
          ...parentPath,
          (slot: 'floatingActionButton', index: i),
        ],
        rect: rect,
        out: out,
      );
    }
  }

  // Anything else (drawer, endDrawer, persistentFooterButtons, ...) we
  // do not have a dedicated geometry for in M13. They're still
  // reachable in the outline; skipping them here keeps the canvas
  // honest about what it can mimic.
}

void _placeSlotChildren({
  required List<ModelNode> children,
  required String slotName,
  required Rect rect,
  required NodePath parentPath,
  required List<CanvasRect> out,
  required bool horizontal,
}) {
  if (children.length == 1) {
    _layoutNode(
      node: children.first,
      path: <NodePathSegment>[...parentPath, (slot: slotName, index: 0)],
      rect: rect,
      out: out,
    );
    return;
  }
  final pairs = <(NodePathSegment, ModelNode)>[
    for (var i = 0; i < children.length; i++)
      ((slot: slotName, index: i), children[i]),
  ];
  _splitAxis(pairs, rect, parentPath, out, horizontal: horizontal);
}

enum _LayoutMode { horizontal, vertical, overlay, inset }

/// Picks a layout mode from the parent widget's class name. Generic
/// fallback distinguishes single-child wrappers (inset) from multi-
/// child compounds (vertical stack — a safe default since we can't
/// know the real layout without running user code).
_LayoutMode _modeFor(WidgetNode parent) {
  if (_kHorizontalWidgets.contains(parent.className)) {
    return _LayoutMode.horizontal;
  }
  if (_kVerticalWidgets.contains(parent.className)) {
    return _LayoutMode.vertical;
  }
  if (_kOverlayWidgets.contains(parent.className)) {
    return _LayoutMode.overlay;
  }
  final total = parent.childSlots.values.fold<int>(0, (a, b) => a + b.length);
  if (total <= 1) return _LayoutMode.inset;
  return _LayoutMode.vertical;
}

const Set<String> _kHorizontalWidgets = <String>{
  'Row',
  'Flex',
  'Wrap',
  'ButtonBar',
  'OverflowBar',
};

const Set<String> _kVerticalWidgets = <String>{
  'Column',
  'ListView',
  'GridView',
  'CustomScrollView',
  'SingleChildScrollView',
  'ListBody',
  'Form',
  'ExpansionPanelList',
};

const Set<String> _kOverlayWidgets = <String>{
  'Stack',
  'IndexedStack',
  'Positioned',
};
