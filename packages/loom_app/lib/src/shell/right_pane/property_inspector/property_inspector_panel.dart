import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../inspectors/property_editor_router.dart';
import '../../../services/kernel_adapter.dart';
import '../../../state/providers.dart';

/// Bottom of the right pane. Shows one row per editable property on
/// the currently-selected widget. Empty/idle states explain what's
/// missing — no selection, parse failure, etc.
class PropertyInspectorPanel extends ConsumerWidget {
  const PropertyInspectorPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeDocumentUriProvider);
    final selectedPath = ref.watch(selectedNodePathProvider);
    final theme = Theme.of(context);

    if (active == null || selectedPath == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Select a node to edit its properties.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ),
      );
    }

    final parseResult = ref.watch(widgetTreeForDocumentProvider(active));
    if (parseResult is WidgetTreeParseFailure) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Parse failed: ${parseResult.message}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ),
      );
    }

    final model = (parseResult as WidgetTreeParseModeled).model;
    final node = model.nodeAt(selectedPath);
    if (node is! WidgetNode) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Selected node has no editable properties.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ),
      );
    }

    final entries = node.properties.entries
        .where((e) => !e.key.startsWith(kPositionalOpaqueKeyPrefix))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          height: 32,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: Text(
            node.namedConstructor == null
                ? node.className
                : '${node.className}.${node.namedConstructor}',
            style: theme.textTheme.titleSmall,
          ),
        ),
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      '${node.className} has no editable properties.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, i) {
                    final entry = entries[i];
                    return PropertyEditorRouter(
                      documentUri: active,
                      nodePath: selectedPath,
                      propertyName: entry.key,
                      propertyValue: entry.value,
                    );
                  },
                ),
        ),
      ],
    );
  }
}
