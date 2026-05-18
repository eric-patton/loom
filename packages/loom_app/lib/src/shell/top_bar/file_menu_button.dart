import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';

/// "File" menu in the top bar. M11 surface: Open Project… only.
/// Close-project, save-as, recent-projects, etc. arrive in M12+.
class FileMenuButton extends ConsumerWidget {
  const FileMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MenuAnchor(
      menuChildren: <Widget>[
        MenuItemButton(
          onPressed: () async {
            // MenuItemButton fires onPressed inside a frame callback, and
            // file_picker's getDirectoryPath calls IModalWindow.show, which
            // runs a nested Win32 message pump. Showing the dialog while the
            // scheduler is mid-frame trips the
            // `schedulerPhase == SchedulerPhase.idle` assertion. Wait for the
            // current frame to finish before opening the dialog.
            await WidgetsBinding.instance.endOfFrame;
            final selected = await FilePicker.platform.getDirectoryPath(
              dialogTitle: 'Open Loom project',
            );
            if (selected != null) {
              await ref.read(workspaceControllerProvider).openProject(selected);
            }
          },
          child: const Text('Open Project…'),
        ),
      ],
      builder: (context, controller, _) {
        return TextButton(
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
          child: const Text('File'),
        );
      },
    );
  }
}
