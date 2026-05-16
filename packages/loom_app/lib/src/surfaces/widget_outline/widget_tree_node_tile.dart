import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/kernel_adapter.dart';
import '../../state/providers.dart';
import 'node_display_label.dart';

/// One row in the outline. Indents by `path.length * 16px`, paints the
/// selection background, and updates `selectedNodePathProvider` on tap.
class WidgetTreeNodeTile extends ConsumerWidget {
  const WidgetTreeNodeTile({
    super.key,
    required this.documentUri,
    required this.path,
    required this.node,
  });

  final String documentUri;
  final NodePath path;
  final ModelNode node;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedNodePathProvider);
    final isSelected = selected != null && listEquals(selected, path);
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => ref.read(selectedNodePathProvider.notifier).state = path,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          12.0 + path.length * 16.0,
          4,
          12,
          4,
        ),
        color: isSelected ? theme.colorScheme.primaryContainer : null,
        child: NodeDisplayLabel(node: node),
      ),
    );
  }
}
