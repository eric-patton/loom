import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../../services/kernel_adapter.dart';
import 'canvas_layout.dart';
import 'canvas_node_label.dart';
import 'canvas_rect.dart';

/// Paints every [CanvasRect] in pre-order so containers paint before
/// their children. Selection draws a thick primary-color border;
/// hover draws a thinner accent-color border below the selection
/// border so both can be visible at once.
class WidgetCanvasPainter extends CustomPainter {
  WidgetCanvasPainter({
    required this.layout,
    required this.selectedPath,
    required this.hoveredPath,
    required this.colorScheme,
    required this.textTheme,
  });

  final CanvasLayout layout;
  final NodePath? selectedPath;
  final NodePath? hoveredPath;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  void paint(Canvas canvas, Size size) {
    for (final r in layout.rects) {
      _paintRect(canvas, r);
    }
  }

  void _paintRect(Canvas canvas, CanvasRect r) {
    final isSelected = selectedPath != null && listEquals(selectedPath, r.path);
    final isHovered = hoveredPath != null && listEquals(hoveredPath, r.path);

    final fill = _fillFor(r.node).withValues(alpha: 0.08);
    canvas.drawRect(r.rect, Paint()..color = fill);

    final labelHeight = r.rect.height >= 22 ? 20.0 : r.rect.height;
    if (labelHeight > 4) {
      final labelRect = Rect.fromLTWH(
        r.rect.left,
        r.rect.top,
        r.rect.width,
        labelHeight,
      );
      canvas.drawRect(
        labelRect,
        Paint()..color = _fillFor(r.node).withValues(alpha: 0.18),
      );
    }

    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = isSelected ? 2.5 : (isHovered ? 1.5 : 1.0)
      ..color = isSelected
          ? colorScheme.primary
          : (isHovered ? colorScheme.tertiary : colorScheme.outlineVariant);
    canvas.drawRect(r.rect, border);

    _paintLabel(canvas, r);
  }

  void _paintLabel(Canvas canvas, CanvasRect r) {
    if (r.rect.width < 28 || r.rect.height < 14) return;
    final tp = TextPainter(
      text: TextSpan(
        text: canvasLabelFor(r.node),
        style: textTheme.labelSmall?.copyWith(
          color: _labelColor(r.node),
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: r.rect.width - 8);
    tp.paint(canvas, Offset(r.rect.left + 4, r.rect.top + 2));
  }

  Color _fillFor(ModelNode node) {
    return switch (node) {
      WidgetNode() => colorScheme.primary,
      MethodReferenceNode() => colorScheme.tertiary,
      OpaqueNode() => colorScheme.outline,
      _ => colorScheme.error,
    };
  }

  Color _labelColor(ModelNode node) {
    return switch (node) {
      WidgetNode() => colorScheme.onSurface,
      MethodReferenceNode() => colorScheme.tertiary,
      OpaqueNode() => colorScheme.onSurfaceVariant,
      _ => colorScheme.error,
    };
  }

  @override
  bool shouldRepaint(WidgetCanvasPainter old) =>
      old.layout != layout ||
      !listEquals(old.selectedPath, selectedPath) ||
      !listEquals(old.hoveredPath, hoveredPath) ||
      old.colorScheme != colorScheme;
}
