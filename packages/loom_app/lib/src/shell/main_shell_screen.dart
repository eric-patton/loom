import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import 'center/center_editor_surface.dart';
import 'left_rail/left_rail_toolbox.dart';
import 'right_pane/right_split_pane.dart';
import 'top_bar/top_app_bar.dart';

/// Intent fired by Ctrl+Z anywhere outside a text field.
class _UndoWorkspaceIntent extends Intent {
  const _UndoWorkspaceIntent();
}

/// Intent fired by Ctrl+Y or Ctrl+Shift+Z anywhere outside a text field.
class _RedoWorkspaceIntent extends Intent {
  const _RedoWorkspaceIntent();
}

/// The root composition: top bar across the top, then a three-column
/// row beneath — left rail (toolbox), center editor surface, right
/// pane (top tabs + property inspector).
///
/// A top-level `Shortcuts` + `Actions` block binds Ctrl+Z / Ctrl+Y /
/// Ctrl+Shift+Z to workspace undo/redo. The bindings only fire when
/// focus is NOT inside a text field — `EditableText` consumes its own
/// undo events at a lower level, so typing inside the property
/// inspector still undoes characters before bubbling up to the
/// workspace.
class MainShellScreen extends ConsumerWidget {
  const MainShellScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.keyZ, control: true):
            _UndoWorkspaceIntent(),
        SingleActivator(LogicalKeyboardKey.keyY, control: true):
            _RedoWorkspaceIntent(),
        SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true):
            _RedoWorkspaceIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _UndoWorkspaceIntent: CallbackAction<_UndoWorkspaceIntent>(
            onInvoke: (_) {
              unawaited(ref.read(workspaceControllerProvider).undo());
              return null;
            },
          ),
          _RedoWorkspaceIntent: CallbackAction<_RedoWorkspaceIntent>(
            onInvoke: (_) {
              unawaited(ref.read(workspaceControllerProvider).redo());
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: Column(
              children: const <Widget>[
                TopAppBar(),
                Expanded(
                  child: Row(
                    children: <Widget>[
                      SizedBox(width: 220, child: LeftRailToolbox()),
                      VerticalDivider(width: 1),
                      Expanded(child: CenterEditorSurface()),
                      VerticalDivider(width: 1),
                      SizedBox(width: 360, child: RightSplitPane()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
