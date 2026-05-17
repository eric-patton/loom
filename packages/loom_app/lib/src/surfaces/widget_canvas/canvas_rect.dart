import 'package:flutter/widgets.dart';

import '../../services/kernel_adapter.dart';

/// One rectangle in a [CanvasLayout]. The painter walks the list to
/// render rects in pre-order (parents before children) so that nested
/// rects paint on top of their containers.
class CanvasRect {
  const CanvasRect({
    required this.path,
    required this.rect,
    required this.node,
  });

  /// Path to this node in the source `WidgetTreeModel`. Empty for the
  /// root.
  final NodePath path;

  /// Geometry on the canvas. Origin is the canvas widget's top-left
  /// corner.
  final Rect rect;

  /// The underlying model node — `WidgetNode` for tree-structured
  /// recognitions, `OpaqueNode` / `MethodReferenceNode` etc. for
  /// stand-ins. The painter discriminates on this to pick label /
  /// color / fill.
  final ModelNode node;
}
