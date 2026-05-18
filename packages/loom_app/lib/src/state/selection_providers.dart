import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/kernel_adapter.dart';

/// A selection that records BOTH the node's path AND the document the
/// path is rooted in. Introduced in M13.5 so the canvas can select a
/// node from a *resolved user widget* (e.g. clicking text rendered from
/// `counter.dart` while `main.dart` is the active editor): the path is
/// rooted at counter.dart's parsed tree, even though the canvas was
/// driven by main.dart.
typedef NodeSelection = ({String documentUri, NodePath path});

/// The currently-selected node, or null when nothing is selected.
/// Shared across the outline view, the property inspector, and the
/// canvas. Edits driven off a selection commit to `selection.documentUri`,
/// which may differ from the active editor tab when selecting through
/// a resolved user widget.
final selectedNodeProvider = StateProvider<NodeSelection?>((ref) => null);

/// The node the user is currently hovering over in the canvas, or null
/// when no hover is active. The outline does not contribute to or read
/// from this provider — it's a canvas-specific affordance.
final hoveredNodeProvider = StateProvider<NodeSelection?>((ref) => null);

/// Path-only view of [selectedNodeProvider] for non-canvas callers that
/// don't yet need cross-document selection. Soft-deprecated — new
/// readers should consume [selectedNodeProvider] directly so they pick
/// up `selection.documentUri`. Drops to null when the active editor
/// tab differs from the selection's source document, so consumers that
/// read this provider against the active document don't accidentally
/// dereference a cross-file path.
final selectedNodePathProvider = Provider<NodePath?>((ref) {
  final selection = ref.watch(selectedNodeProvider);
  return selection?.path;
});

/// Path-only view of [hoveredNodeProvider] (see [selectedNodePathProvider]).
final hoveredNodePathProvider = Provider<NodePath?>((ref) {
  final hovered = ref.watch(hoveredNodeProvider);
  return hovered?.path;
});

/// Which top-tab the right pane has focus on.
enum RightTopTab { interface, outline }

final rightTopTabProvider =
    StateProvider<RightTopTab>((ref) => RightTopTab.interface);

/// M11-placeholder toolbox categories. The left-rail toolbox renders
/// this list; M11 ships an empty list and a "M14" stub badge. M14
/// will replace this with the real catalog-driven content.
class ToolboxCategory {
  const ToolboxCategory({required this.name, required this.items});
  final String name;
  final List<ToolboxItem> items;
}

class ToolboxItem {
  const ToolboxItem({required this.displayName, required this.className});
  final String displayName;
  final String className;
}

final toolboxItemsProvider = Provider<List<ToolboxCategory>>(
  (ref) => const <ToolboxCategory>[],
);
