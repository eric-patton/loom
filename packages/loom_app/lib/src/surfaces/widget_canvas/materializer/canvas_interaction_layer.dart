import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/kernel_adapter.dart';
import '../../../state/selection_providers.dart';
import '../inline_text_edit_state.dart';
import 'materialize_ctx.dart';

/// One outer `MouseRegion` + `Listener` for the whole materialized
/// tree. Translates pointer coordinates into the deepest [ProbeEntry]
/// at that point (by walking the per-frame `probes` map and using each
/// probe's `GlobalKey` to read its `RenderBox` bounds) and writes the
/// matching `NodeSelection` to the providers.
///
/// Single-listener (vs. per-widget Listener) keeps event semantics
/// trivial: Flutter's hit-test order on nested PointerListeners is
/// "every ancestor receives the event", which makes "deepest wins"
/// awkward to express. Doing the hit-test ourselves against the probe
/// registry is straightforward and matches the M13-painter's
/// rect-based approach in spirit.
class CanvasInteractionLayer extends ConsumerStatefulWidget {
  const CanvasInteractionLayer({
    super.key,
    required this.probes,
    required this.child,
  });

  /// The probe map filled in during this frame's materialize pass.
  /// Read on each pointer event to identify the deepest hit.
  final Map<String, ProbeEntry> probes;
  final Widget child;

  @override
  ConsumerState<CanvasInteractionLayer> createState() =>
      _CanvasInteractionLayerState();
}

class _CanvasInteractionLayerState
    extends ConsumerState<CanvasInteractionLayer> {
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: _handleHover,
      onExit: (_) {
        if (mounted) {
          ref.read(hoveredNodeProvider.notifier).state = null;
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) => _handleTap(details.globalPosition),
        onDoubleTapDown: (details) => _handleDoubleTap(details.globalPosition),
        child: widget.child,
      ),
    );
  }

  void _handleHover(PointerHoverEvent event) {
    final hit = _hitTest(event.position);
    final current = ref.read(hoveredNodeProvider);
    final next = hit?.selection;
    if (!_selectionsEqual(current, next)) {
      ref.read(hoveredNodeProvider.notifier).state = next;
    }
  }

  void _handleTap(Offset globalPosition) {
    final hit = _hitTest(globalPosition);
    if (hit == null) {
      ref.read(selectedNodeProvider.notifier).state = null;
      return;
    }
    final altPressed = HardwareKeyboard.instance.logicalKeysPressed.any(
      (k) =>
          k == LogicalKeyboardKey.altLeft || k == LogicalKeyboardKey.altRight,
    );
    final current = ref.read(selectedNodeProvider);
    NodeSelection target = hit.selection;
    if (altPressed &&
        current != null &&
        current.documentUri == hit.selection.documentUri &&
        listEquals(current.path, hit.selection.path) &&
        current.path.isNotEmpty) {
      // Alt+click on the already-selected leaf promotes to its
      // parent.
      final promoted = <NodePathSegment>[...current.path]..removeLast();
      target = (documentUri: current.documentUri, path: promoted);
    }
    ref.read(selectedNodeProvider.notifier).state = target;
  }

  void _handleDoubleTap(Offset globalPosition) {
    final hit = _hitTest(globalPosition);
    if (hit == null) return;
    final node = hit.node;
    if (node is! WidgetNode) return;
    if (node.className != 'Text') return;
    final data = node.properties['data'];
    if (data is! StringLiteralValue) return;
    ref.read(inlineTextEditProvider.notifier).state = InlineTextEditTarget(
      documentUri: hit.selection.documentUri,
      nodePath: hit.selection.path,
      original: data,
    );
    ref.read(selectedNodeProvider.notifier).state = hit.selection;
  }

  /// Walks the probe registry and returns the deepest entry whose
  /// `RenderBox` bounds contain [globalPosition], or null if no probe
  /// is under that point.
  ProbeEntry? _hitTest(Offset globalPosition) {
    ProbeEntry? best;
    for (final entry in widget.probes.values) {
      final rect = _rectFor(entry.key);
      if (rect == null || !rect.contains(globalPosition)) continue;
      if (best == null || entry.depth > best.depth) {
        best = entry;
      }
    }
    return best;
  }

  Rect? _rectFor(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return null;
    final renderObject = ctx.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    final topLeft = renderObject.localToGlobal(Offset.zero);
    return topLeft & renderObject.size;
  }

  static bool _selectionsEqual(NodeSelection? a, NodeSelection? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    if (a.documentUri != b.documentUri) return false;
    return listEquals(a.path, b.path);
  }
}
