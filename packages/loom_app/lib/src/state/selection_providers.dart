import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/kernel_adapter.dart';

/// The currently-selected node path in the active document, or null
/// when nothing is selected. Shared across the outline view, the
/// property inspector, and (post-M13) the canvas — all three panes
/// agree on selection through this single provider.
final selectedNodePathProvider = StateProvider<NodePath?>((ref) => null);

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
