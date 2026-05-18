import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../state/selection_providers.dart';
import 'materialize_ctx.dart';

/// Top-of-stack overlay that paints thin borders around the selected
/// and hovered probes. Reads the probe registry built during this
/// frame's materialize pass to convert `NodeSelection` paths into
/// screen rects, then translates those into overlay-local coordinates
/// for a `CustomPaint`.
class CanvasSelectionOverlay extends ConsumerStatefulWidget {
  const CanvasSelectionOverlay({super.key, required this.probes});

  final Map<String, ProbeEntry> probes;

  @override
  ConsumerState<CanvasSelectionOverlay> createState() =>
      _CanvasSelectionOverlayState();
}

class _CanvasSelectionOverlayState
    extends ConsumerState<CanvasSelectionOverlay> {
  @override
  void initState() {
    super.initState();
    // Selection/hover writes happen via providers and pump frames
    // naturally. We schedule an extra rebuild after the first frame so
    // our `context.findRenderObject()` returns a valid laid-out box
    // (its size/origin is required to convert probe global coords to
    // overlay-local coords). Without this the FIRST frame after a
    // selection sometimes paints at screen-origin instead of pane-origin.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final selection = ref.watch(selectedNodeProvider);
    final hover = ref.watch(hoveredNodeProvider);
    if (selection == null && hover == null) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final overlayBox = context.findRenderObject();
    Offset overlayOrigin = Offset.zero;
    if (overlayBox is RenderBox && overlayBox.hasSize) {
      overlayOrigin = overlayBox.localToGlobal(Offset.zero);
    } else {
      // Render object isn't laid out yet — schedule another rebuild
      // for the next frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
    final selectedKey = selection == null
        ? null
        : widget.probes[MaterializeCtx.probeRegistryKey(selection)]?.key;
    final hoveredKey = hover == null
        ? null
        : widget.probes[MaterializeCtx.probeRegistryKey(hover)]?.key;
    return IgnorePointer(
      child: CustomPaint(
        painter: _SelectionBorderPainter(
          selectedRect: _rectFor(selectedKey, overlayOrigin),
          hoveredRect: _rectFor(hoveredKey, overlayOrigin),
          selectedColor: theme.colorScheme.primary,
          hoveredColor: theme.colorScheme.tertiary,
        ),
        size: Size.infinite,
      ),
    );
  }

  Rect? _rectFor(GlobalKey? key, Offset overlayOrigin) {
    if (key == null) return null;
    final ctx = key.currentContext;
    if (ctx == null) return null;
    final ro = ctx.findRenderObject();
    if (ro is! RenderBox || !ro.hasSize) return null;
    final probeTopLeft = ro.localToGlobal(Offset.zero);
    return (probeTopLeft - overlayOrigin) & ro.size;
  }
}

class _SelectionBorderPainter extends CustomPainter {
  _SelectionBorderPainter({
    required this.selectedRect,
    required this.hoveredRect,
    required this.selectedColor,
    required this.hoveredColor,
  });

  final Rect? selectedRect;
  final Rect? hoveredRect;
  final Color selectedColor;
  final Color hoveredColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (hoveredRect != null && hoveredRect != selectedRect) {
      final paint = Paint()
        ..color = hoveredColor.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawRect(hoveredRect!, paint);
    }
    if (selectedRect != null) {
      final paint = Paint()
        ..color = selectedColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      canvas.drawRect(selectedRect!, paint);
    }
  }

  @override
  bool shouldRepaint(_SelectionBorderPainter old) =>
      old.selectedRect != selectedRect ||
      old.hoveredRect != hoveredRect ||
      old.selectedColor != selectedColor ||
      old.hoveredColor != hoveredColor;
}
