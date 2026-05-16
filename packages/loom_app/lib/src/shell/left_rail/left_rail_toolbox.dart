import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';

/// M11 placeholder. The plan defers the real catalog-driven toolbox to
/// M14; this widget exists so the three-pane shell already has a left
/// rail to lay out against and the M14 work is a pure content swap.
class LeftRailToolbox extends ConsumerWidget {
  const LeftRailToolbox({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final categories = ref.watch(toolboxItemsProvider);
    return Container(
      color: theme.colorScheme.surfaceContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            height: 36,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            child: Text('Toolbox', style: theme.textTheme.titleSmall),
          ),
          Expanded(
            child: categories.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Drag-drop toolbox lands in M14.\n'
                        'For now, click a node in the outline to edit '
                        'its properties.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: categories.length,
                    itemBuilder: (_, __) => const SizedBox.shrink(),
                  ),
          ),
        ],
      ),
    );
  }
}
