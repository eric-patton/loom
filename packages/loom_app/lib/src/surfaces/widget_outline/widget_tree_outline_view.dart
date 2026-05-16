import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/kernel_adapter.dart';
import '../../state/providers.dart';
import 'widget_tree_node_tile.dart';

/// Pre-order indented list of every node in the active document's
/// widget tree. The M11 editor surface — no canvas. Selection here
/// drives the property inspector.
class WidgetTreeOutlineView extends ConsumerWidget {
  const WidgetTreeOutlineView({super.key, required this.documentUri});

  final String documentUri;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(widgetTreeForDocumentProvider(documentUri));
    final theme = Theme.of(context);

    if (result is WidgetTreeParseFailure) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Parse failed: ${result.message}',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }

    final model = (result as WidgetTreeParseModeled).model;
    final entries = model.walk();

    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, i) {
        return WidgetTreeNodeTile(
          documentUri: documentUri,
          path: entries[i].path,
          node: entries[i].node,
        );
      },
    );
  }
}
