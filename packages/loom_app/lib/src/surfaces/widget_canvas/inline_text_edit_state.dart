import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/kernel_adapter.dart';

/// Identifies an in-progress inline edit: the document, the path to
/// the `Text` widget, and the original `StringLiteralValue` that
/// the user double-clicked. Holding the original value here lets the
/// commit path call `WorkspaceController.applyPropertyEdit(oldValue:
/// …, newValue: …)` without a re-parse round-trip.
class InlineTextEditTarget {
  const InlineTextEditTarget({
    required this.documentUri,
    required this.nodePath,
    required this.original,
  });

  final String documentUri;
  final NodePath nodePath;
  final StringLiteralValue original;
}

/// Active inline edit on the canvas, or null when none. Only ever one
/// at a time — double-clicking a different `Text` replaces the
/// previous edit (which auto-commits via its `FocusNode` losing
/// focus).
final inlineTextEditProvider = StateProvider<InlineTextEditTarget?>(
  (ref) => null,
);
