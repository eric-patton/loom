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
