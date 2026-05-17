import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';

/// Horizontal strip of tabs across the top of the center pane — one
/// per open document. Click a tab to focus it; the small X button
/// closes it (prompting first if the document has uncommitted edits).
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
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Tooltip(
                        message: 'Unsaved changes — last save did not '
                            'reach disk.',
                        child: Text(
                          '●',
                          style: TextStyle(
                            color: theme.colorScheme.error,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  Text(doc.displayName),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () => _maybeClose(context, ref, uri, doc.isDirty),
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

  Future<void> _maybeClose(
    BuildContext context,
    WidgetRef ref,
    String uri,
    bool isDirty,
  ) async {
    if (!isDirty) {
      ref.read(workspaceControllerProvider).closeFile(uri);
      return;
    }
    final choice = await showDialog<_CloseChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: const Text(
          'This document has edits that did not reach disk. Close '
          'anyway? Closing discards the in-memory buffer.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_CloseChoice.cancel),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_CloseChoice.discard),
            child: const Text('Discard and close'),
          ),
        ],
      ),
    );
    if (choice == _CloseChoice.discard) {
      ref.read(workspaceControllerProvider).closeFile(uri);
    }
  }
}

enum _CloseChoice { cancel, discard }
