import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';

/// Horizontal strip of tabs across the top of the center pane — one
/// per open document. Click a tab to focus it; the small X button
/// closes it.
class EditorTabStrip extends ConsumerWidget {
  const EditorTabStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docs = ref.watch(openDocumentsProvider);
    final active = ref.watch(activeDocumentUriProvider);
    final theme = Theme.of(context);
    final entries = docs.entries.toList();
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: entries.length,
        itemBuilder: (context, i) {
          final entry = entries[i];
          final uri = entry.key;
          final doc = entry.value;
          final isActive = uri == active;
          return InkWell(
            onTap: () => ref.read(workspaceControllerProvider).openFile(uri),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color:
                    isActive ? theme.colorScheme.surfaceContainerHighest : null,
                border: Border(
                  right: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (doc.isDirty)
                    const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: Text('●'),
                    ),
                  Text(doc.displayName),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () =>
                        ref.read(workspaceControllerProvider).closeFile(uri),
                    child: const Icon(Icons.close, size: 14),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
