import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../state/providers.dart';

/// Slim toolbar that sits above the property inspector when a document
/// is active. Toggles per-document `formatOnSave` — opt-in by design,
/// because byte-minimal diffs are the editor's product invariant and
/// `dart_style` does not respect them.
class FormatOnSaveBar extends ConsumerWidget {
  const FormatOnSaveBar({super.key, required this.documentUri});

  final String documentUri;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(formatOnSaveProvider)[documentUri] ?? false;
    final theme = Theme.of(context);
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              'Format on save',
              style: theme.textTheme.bodySmall,
            ),
          ),
          Tooltip(
            message: enabled
                ? 'dart_style will rewrite the whole file on each '
                    'property edit, breaking byte-minimal diffs.'
                : 'Off: edits preserve everything outside the changed '
                    'span. (Recommended.)',
            child: Switch(
              value: enabled,
              onChanged: (v) =>
                  ref.read(formatOnSaveProvider.notifier).set(documentUri, v),
            ),
          ),
        ],
      ),
    );
  }
}
