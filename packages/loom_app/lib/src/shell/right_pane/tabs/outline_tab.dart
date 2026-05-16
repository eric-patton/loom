import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../state/providers.dart';
import '../../../surfaces/widget_outline/widget_tree_outline_view.dart';

/// Right-pane Outline tab. Mirrors the center pane's outline so a user
/// who has moved the center to a future surface (canvas, in M13) can
/// still drive selection from the right. In M11 it simply shows the
/// same widget tree the center renders.
class OutlineTab extends ConsumerWidget {
  const OutlineTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeDocumentUriProvider);
    if (active == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Open a file to see its widget outline.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
    }
    return WidgetTreeOutlineView(documentUri: active);
  }
}
