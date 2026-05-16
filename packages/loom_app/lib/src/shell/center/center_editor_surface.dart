import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import 'active_editor_router.dart';
import 'editor_tab_strip.dart';

/// The center column. M11 renders the editor tab strip (when any tab
/// is open) above a single editor surface; the active editor is
/// selected by [ActiveEditorRouter] based on the focused tab's mode.
class CenterEditorSurface extends ConsumerWidget {
  const CenterEditorSurface({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docs = ref.watch(openDocumentsProvider);
    return Column(
      children: <Widget>[
        if (docs.isNotEmpty) const EditorTabStrip(),
        const Expanded(child: ActiveEditorRouter()),
      ],
    );
  }
}
