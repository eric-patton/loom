import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/kernel_adapter.dart';
import '../../state/providers.dart';
import 'inline_text_edit_state.dart';
import 'inline_text_editor.dart';
import 'materializer/canvas_interaction_layer.dart';
import 'materializer/canvas_viewport.dart';
import 'materializer/materialize_ctx.dart';
import 'materializer/node_materializer.dart';
import 'materializer/selection_overlay.dart';

/// Primary editor surface for a Dart document. Materializes the
/// model's widget tree into real Flutter widgets so the canvas paints
/// a faithful approximation of the rendered page (M13.5), recursing
/// into user-defined widgets via `userWidgetResolutionProvider`. The
/// model is still the only source of truth — no user code runs.
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
    return _MaterializedCanvas(documentUri: documentUri, model: model);
  }
}

/// Builds the materialized tree, the interaction layer, and the
/// selection overlay around a single document's model. Holds the
/// per-frame probe registry so all three layers share it without
/// going through global state.
class _MaterializedCanvas extends ConsumerWidget {
  const _MaterializedCanvas({required this.documentUri, required this.model});

  final String documentUri;
  final WidgetTreeModel model;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Fresh probe registry per build. Filled in by NodeMaterializer's
    // recursion below; read by the interaction layer and the selection
    // overlay on the same frame.
    final probes = <String, ProbeEntry>{};
    final ctx = MaterializeCtx(
      sourceDocumentUri: documentUri,
      ref: ref,
      probes: probes,
    );
    final materialized =
        NodeMaterializer.materialize(model.root, const [], ctx);

    final inlineEdit = ref.watch(inlineTextEditProvider);

    return CanvasViewport(
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // Bottom: the materialized tree itself, hosted in the
          // interaction layer that translates clicks into selection.
          CanvasInteractionLayer(
            probes: probes,
            child: materialized,
          ),
          // Middle: the selection / hover borders. Pointer-transparent
          // so clicks land on the interaction layer beneath.
          Positioned.fill(child: CanvasSelectionOverlay(probes: probes)),
          // Top: the inline editor, positioned over the editing node's
          // probe rect.
          if (inlineEdit != null)
            _InlineEditorOverlay(target: inlineEdit, probes: probes),
        ],
      ),
    );
  }
}

class _InlineEditorOverlay extends StatelessWidget {
  const _InlineEditorOverlay({required this.target, required this.probes});

  final InlineTextEditTarget target;
  final Map<String, ProbeEntry> probes;

  @override
  Widget build(BuildContext context) {
    final key = probes[MaterializeCtx.probeRegistryKey(
      (documentUri: target.documentUri, path: target.nodePath),
    )]
        ?.key;
    if (key == null) return const SizedBox.shrink();
    return _PositionedFollowingKey(
      anchor: key,
      child: InlineTextEditor(target: target),
    );
  }
}

/// Positions [child] over [anchor]'s screen rect each frame. Used so
/// the inline editor follows reflows when the underlying Text widget
/// moves (e.g. as its data changes).
class _PositionedFollowingKey extends StatefulWidget {
  const _PositionedFollowingKey({required this.anchor, required this.child});

  final GlobalKey anchor;
  final Widget child;

  @override
  State<_PositionedFollowingKey> createState() =>
      _PositionedFollowingKeyState();
}

class _PositionedFollowingKeyState extends State<_PositionedFollowingKey> {
  @override
  Widget build(BuildContext context) {
    final overlayRO = context.findRenderObject();
    final overlayOrigin = overlayRO is RenderBox && overlayRO.hasSize
        ? overlayRO.localToGlobal(Offset.zero)
        : Offset.zero;
    final anchorCtx = widget.anchor.currentContext;
    final ro = anchorCtx?.findRenderObject();
    if (ro is! RenderBox || !ro.hasSize) {
      // Anchor not laid out yet — schedule a rebuild after this frame
      // so we render once the geometry is available.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
      return const SizedBox.shrink();
    }
    final topLeft = ro.localToGlobal(Offset.zero) - overlayOrigin;
    final size = ro.size;
    return Positioned(
      left: topLeft.dx,
      top: topLeft.dy,
      width: size.width,
      height: size.height,
      child: widget.child,
    );
  }
}
