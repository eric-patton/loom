import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'property_inspector/property_inspector_panel.dart';
import 'right_top_tab_bar.dart';

/// The right column. Top half hosts the tab bar + content (Interface
/// or Outline, M11); the bottom half is the property inspector.
class RightSplitPane extends ConsumerWidget {
  const RightSplitPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainer,
      child: const Column(
        children: <Widget>[
          Expanded(child: RightTopTabBar()),
          Divider(height: 1),
          SizedBox(
            height: 280,
            child: PropertyInspectorPanel(),
          ),
        ],
      ),
    );
  }
}
