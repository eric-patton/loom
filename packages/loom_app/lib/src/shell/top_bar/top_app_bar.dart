import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import 'file_menu_button.dart';

/// The slim top bar: app name, file menu, and an unobtrusive readout of
/// the currently-open project's root.
class TopAppBar extends ConsumerWidget {
  const TopAppBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ps = ref.watch(projectControllerProvider);
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: <Widget>[
          Text(
            'Loom',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 16),
          const FileMenuButton(),
          const Spacer(),
          if (ps != null)
            Flexible(
              child: Text(
                ps.snapshot.rootPath,
                style: theme.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
              ),
            ),
        ],
      ),
    );
  }
}
