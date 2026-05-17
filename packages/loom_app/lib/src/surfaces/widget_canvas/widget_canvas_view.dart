import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/kernel_adapter.dart';
import '../../state/providers.dart';
import 'canvas_layout.dart';
import 'inline_text_edit_state.dart';
import 'inline_text_editor.dart';
import 'widget_canvas_painter.dart';

/// Primary editor surface for a Dart document since M13: a low-fidelity
/// recreation of the widget tree drawn as nested labeled rectangles.
/// Click to select; hover to preview-highlight; double-click a `Text`
/// to inline-edit its `data:` literal. The model is the only source —
/// nothing here runs user code, so the canvas is safe against
/// `compile-time-error` files.
class WidgetCanvasView extends ConsumerWidget {
  const WidgetCanvasView({super.key, required this.documentUri});

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
    return _CanvasInteractive(documentUri: documentUri, model: model);
  }
}

class _CanvasInteractive extends ConsumerStatefulWidget {
  const _CanvasInteractive({required this.documentUri, required this.model});

  final String documentUri;
  final WidgetTreeModel model;

  @override
  ConsumerState<_CanvasInteractive> createState() => _CanvasInteractiveState();
}

class _CanvasInteractiveState extends ConsumerState<_CanvasInteractive> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = ref.watch(selectedNodePathProvider);
    final hovered = ref.watch(hoveredNodePathProvider);
    final inlineEdit = ref.watch(inlineTextEditProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        const padding = 16.0;
        final canvasRect = Rect.fromLTWH(
          padding,
          padding,
          (constraints.maxWidth - 2 * padding).clamp(0, double.infinity),
          (constraints.maxHeight - 2 * padding).clamp(0, double.infinity),
        );
        final layout = layoutTree(widget.model, canvasRect);

        return MouseRegion(
          onHover: (event) => _updateHover(event.localPosition, layout),
          onExit: (_) =>
              ref.read(hoveredNodePathProvider.notifier).state = null,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => _handleTap(d.localPosition, layout),
            onDoubleTapDown: (d) => _handleDoubleTap(d.localPosition, layout),
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: CustomPaint(
                    painter: WidgetCanvasPainter(
                      layout: layout,
                      selectedPath: selected,
                      hoveredPath: hovered,
                      colorScheme: theme.colorScheme,
                      textTheme: theme.textTheme,
                    ),
                  ),
                ),
                if (inlineEdit != null &&
                    inlineEdit.documentUri == widget.documentUri)
                  _maybeInlineEditor(inlineEdit, layout),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _maybeInlineEditor(
    InlineTextEditTarget target,
    CanvasLayout layout,
  ) {
    for (final r in layout.rects) {
      if (_pathsEqual(r.path, target.nodePath)) {
        return InlineTextEditor(target: target, rect: r.rect);
      }
    }
    // The rect for the editing node fell out of the layout (e.g. the
    // canvas shrank below the min-rect threshold). Drop the edit
    // silently — the user can reopen it from the outline path.
    return const SizedBox.shrink();
  }

  void _updateHover(Offset pos, CanvasLayout layout) {
    final hit = layout.hitTest(pos);
    final current = ref.read(hoveredNodePathProvider);
    final next = hit?.path;
    if (!_pathsEqual(current, next)) {
      ref.read(hoveredNodePathProvider.notifier).state = next;
    }
  }

  void _handleTap(Offset pos, CanvasLayout layout) {
    final hit = layout.hitTest(pos);
    ref.read(selectedNodePathProvider.notifier).state = hit?.path;
  }

  void _handleDoubleTap(Offset pos, CanvasLayout layout) {
    final hit = layout.hitTest(pos);
    if (hit == null) return;
    final node = hit.node;
    if (node is! WidgetNode) return;
    if (node.className != 'Text') return;
    final data = node.properties['data'];
    if (data is! StringLiteralValue) return;
    ref.read(inlineTextEditProvider.notifier).state = InlineTextEditTarget(
      documentUri: widget.documentUri,
      nodePath: hit.path,
      original: data,
    );
    ref.read(selectedNodePathProvider.notifier).state = hit.path;
  }

  bool _pathsEqual(NodePath? a, NodePath? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].slot != b[i].slot || a[i].index != b[i].index) return false;
    }
    return true;
  }
}
