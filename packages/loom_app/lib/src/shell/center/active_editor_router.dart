import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../../surfaces/widget_outline/widget_tree_outline_view.dart';

/// Decides which editor to render for the active document. M11 only has
/// one mode — widget outline — so the routing is trivial. M13's canvas
/// and M15's flow editor land as additional cases here.
class ActiveEditorRouter extends ConsumerWidget {
  const ActiveEditorRouter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeDocumentUriProvider);
    if (active == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Open a project to begin.\n'
            'File → Open Project…',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      );
    }
    return WidgetTreeOutlineView(documentUri: active);
  }
}
