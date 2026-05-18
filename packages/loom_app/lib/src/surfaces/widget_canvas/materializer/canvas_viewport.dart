import 'package:flutter/material.dart';

/// Hosts the materialized widget tree. Provides the inherited widgets
/// the tree expects (Theme, Directionality, MediaQuery sized to the
/// pane) so widgets like Scaffold and MaterialApp can lay themselves
/// out as they would in a real app. Adds a subtle backdrop to
/// distinguish the canvas from the editor chrome around it.
class CanvasViewport extends StatelessWidget {
  const CanvasViewport({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          color: theme.colorScheme.surfaceContainerLow,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(size: constraints.biggest),
            child: Theme(
              data: theme,
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}
