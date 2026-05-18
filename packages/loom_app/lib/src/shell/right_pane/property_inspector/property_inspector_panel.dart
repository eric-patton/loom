import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../inspectors/property_editor_router.dart';
import '../../../services/kernel_adapter.dart';
import '../../../state/providers.dart';
import 'format_on_save_bar.dart';

/// Bottom of the right pane. Shows one row per editable property on
/// the currently-selected widget. Empty/idle states explain what's
/// missing — no selection, parse failure, etc.
///
/// Since M13.5 the inspector reads `selectedNodeProvider` (which
/// carries the selection's source document URI as well as the path),
/// so a selection inside a *resolved user widget* — i.e. a Text
/// rendered from counter.dart while main.dart is the active editor —
/// drives the inspector against the resolved file. A small "Editing
/// in counter.dart [open]" pill renders above the property list when
/// the selection's document differs from the active editor tab.
class PropertyInspectorPanel extends ConsumerWidget {
  const PropertyInspectorPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(selectedNodeProvider);
    final activeUri = ref.watch(activeDocumentUriProvider);
    final theme = Theme.of(context);

    // The document edits will write to: the selection's source doc if
    // there's a selection, otherwise the active editor tab. The
    // FormatOnSaveBar tracks the same document so the toggle is for
    // "the doc your edits affect".
    final editingUri = selection?.documentUri ?? activeUri;

    Widget wrap(Widget body) {
      if (editingUri == null) return body;
      final showPill = selection != null &&
          activeUri != null &&
          selection.documentUri != activeUri;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          FormatOnSaveBar(documentUri: editingUri),
          if (showPill) _CrossFileEditPill(documentUri: selection.documentUri),
          Expanded(child: body),
        ],
      );
    }

    if (selection == null || editingUri == null) {
      return wrap(_idle(theme, 'Select a node to edit its properties.'));
    }

    final parseResult = ref.watch(widgetTreeForDocumentProvider(editingUri));
    if (parseResult is WidgetTreeParseFailure) {
      // For cross-file selection the editing doc may not be open yet
      // (its parsed tree provider returns "Document not open" because
      // there's no OpenDocument entry). Fall back to the kernel
      // resolver — the canvas already proved the tree is resolvable.
      final resolved = _resolvedTreeForSelection(ref, selection);
      if (resolved == null) {
        return wrap(_idle(theme, 'Parse failed: ${parseResult.message}'));
      }
      return wrap(_renderForModel(theme, resolved, selection, editingUri));
    }

    final model = (parseResult as WidgetTreeParseModeled).model;
    return wrap(_renderForModel(theme, model, selection, editingUri));
  }

  /// When the selection's document isn't open as a tab (no OpenDocument
  /// → `WidgetTreeParseFailure: Document not open`), pull the model
  /// from the kernel resolver instead so the inspector still works.
  WidgetTreeModel? _resolvedTreeForSelection(
    WidgetRef ref,
    NodeSelection selection,
  ) {
    // The selection's path may be inside a resolved user widget whose
    // declaring file isn't open in any tab. We don't know the widget's
    // class name from the selection alone; instead, try every resolved
    // tree currently cached. In practice the canvas's most recent
    // materialize pass populated the cache for the active doc's user
    // widgets, so the right tree is usually present.
    //
    // Simplest fallback: re-parse the file via the project model
    // directly. The selection's documentUri is canonicalized.
    final projectModel = ref.read(projectModelProvider);
    final adapter = ref.read(kernelAdapterProvider);
    final index = ref.read(projectWidgetIndexProvider);
    if (projectModel == null || index == null) return null;
    final file = projectModel.files[selection.documentUri];
    if (file == null) return null;
    final parsed = adapter.parseWidgetTreeFor(
      source: file.source,
      projectWidgets: index.widgetsVisibleFrom(selection.documentUri),
    );
    if (parsed is WidgetTreeParseModeled) return parsed.model;
    return null;
  }

  Widget _renderForModel(
    ThemeData theme,
    WidgetTreeModel model,
    NodeSelection selection,
    String editingUri,
  ) {
    final node = model.nodeAt(selection.path);
    if (node is! WidgetNode) {
      return _idle(theme, 'Selected node has no editable properties.');
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
              ? _idle(theme, '${node.className} has no editable properties.')
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, i) {
                    final entry = entries[i];
                    return PropertyEditorRouter(
                      documentUri: editingUri,
                      nodePath: selection.path,
                      propertyName: entry.key,
                      propertyValue: entry.value,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _idle(ThemeData theme, String message) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ),
      );
}

class _CrossFileEditPill extends ConsumerWidget {
  const _CrossFileEditPill({required this.documentUri});

  final String documentUri;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final basename = p.basename(documentUri);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.edit_outlined,
            size: 14,
            color: theme.colorScheme.onTertiaryContainer,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Editing in $basename',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onTertiaryContainer,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () {
              ref.read(workspaceControllerProvider).openFile(documentUri);
            },
            child: Text(
              'Open',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onTertiaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
