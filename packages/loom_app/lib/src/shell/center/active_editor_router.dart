import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../../surfaces/widget_canvas/widget_canvas_view.dart';

/// Decides which editor to render for the active document. Since M13
/// the center pane shows the widget canvas; the outline mirrors in
/// the right pane. M15's flow editor lands as an additional case
/// here.
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
    return WidgetCanvasView(documentUri: active);
  }
}
