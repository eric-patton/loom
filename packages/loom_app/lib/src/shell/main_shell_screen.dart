import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'center/center_editor_surface.dart';
import 'left_rail/left_rail_toolbox.dart';
import 'right_pane/right_split_pane.dart';
import 'top_bar/top_app_bar.dart';

/// The root composition: top bar across the top, then a three-column
/// row beneath — left rail (toolbox), center editor surface, right
/// pane (top tabs + property inspector).
///
/// All measurements are intentionally simple in M11. Drag-to-resize
/// splitters land in M12.
class MainShellScreen extends ConsumerWidget {
  const MainShellScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Column(
        children: const <Widget>[
          TopAppBar(),
          Expanded(
            child: Row(
              children: <Widget>[
                SizedBox(width: 220, child: LeftRailToolbox()),
                VerticalDivider(width: 1),
                Expanded(child: CenterEditorSurface()),
                VerticalDivider(width: 1),
                SizedBox(width: 360, child: RightSplitPane()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
