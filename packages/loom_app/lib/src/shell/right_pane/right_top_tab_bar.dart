import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import 'tabs/interface_tab.dart';
import 'tabs/outline_tab.dart';

/// Top of the right pane: a thin tab bar plus the active tab's body.
/// M11 exposes Interface (file list) and Outline (mirrors the center
/// outline for selection). M14+ tabs (Logic, Process, Data, Structures)
/// land as additional cases in the body switch.
class RightTopTabBar extends ConsumerWidget {
  const RightTopTabBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(rightTopTabProvider);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          height: 36,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: Row(
            children: <Widget>[
              _TabButton(
                label: 'Interface',
                isActive: active == RightTopTab.interface,
                onTap: () => ref.read(rightTopTabProvider.notifier).state =
                    RightTopTab.interface,
              ),
              _TabButton(
                label: 'Outline',
                isActive: active == RightTopTab.outline,
                onTap: () => ref.read(rightTopTabProvider.notifier).state =
                    RightTopTab.outline,
              ),
            ],
          ),
        ),
        Expanded(
          child: switch (active) {
            RightTopTab.interface => const InterfaceTab(),
            RightTopTab.outline => const OutlineTab(),
          },
        ),
      ],
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? theme.colorScheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
            color: isActive ? theme.colorScheme.primary : null,
          ),
        ),
      ),
    );
  }
}
