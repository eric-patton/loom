import '../../services/kernel_adapter.dart';
import '../widget_outline/node_display_label.dart';

/// Generates a short label for a canvas rectangle. Mostly the node's
/// class name, with a few common widgets enriched by content snippets
/// so the canvas feels less like a tree of identical boxes:
///   `Text('Hello')`   → "Text 'Hello'"
///   `SizedBox(100×50)` → "SizedBox 100×50"
///   `Padding(8)`      → "Padding 8"
///
/// Falls back to `NodeDisplayLabel.labelFor` (the outline's shared
/// label) for everything else so the canvas, outline, and inspector
/// header stay in sync.
String canvasLabelFor(ModelNode node) {
  if (node is! WidgetNode) return NodeDisplayLabel.labelFor(node);

  switch (node.className) {
    case 'Text':
      final data = node.properties['data'];
      if (data is StringLiteralValue) {
        return "Text '${_truncate(data.value, 18)}'";
      }
    case 'SizedBox':
      final w = _numericText(node.properties['width']);
      final h = _numericText(node.properties['height']);
      if (w != null || h != null) {
        return 'SizedBox ${w ?? '?'}×${h ?? '?'}';
      }
    case 'Padding':
      final p = node.properties['padding'];
      if (p is EdgeInsetsAllValue) {
        return 'Padding ${_numStr(p.amount, p.amountIsDouble)}';
      }
    case 'Visibility':
      final v = node.properties['visible'];
      if (v is BoolLiteralValue) {
        return v.value ? 'Visibility ✓' : 'Visibility ✗';
      }
  }
  return NodeDisplayLabel.labelFor(node);
}

String? _numericText(PropertyValue? v) {
  if (v is NumLiteralValue) return _numStr(v.value, v.isDouble);
  return null;
}

String _numStr(num value, bool isDouble) {
  if (isDouble) {
    final asString = value.toString();
    return asString.endsWith('.0')
        ? asString.substring(0, asString.length - 2)
        : asString;
  }
  return value.toString();
}

String _truncate(String text, int maxLen) {
  if (text.length <= maxLen) return text;
  return '${text.substring(0, maxLen - 1)}…';
}
