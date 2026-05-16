import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/kernel_adapter.dart';
import '../state/providers.dart';

/// Edits a `BoolLiteralValue`. One tap commits.
class BoolPropertyEditor extends ConsumerWidget {
  const BoolPropertyEditor({
    super.key,
    required this.documentUri,
    required this.propertyName,
    required this.value,
  });

  final String documentUri;
  final String propertyName;
  final BoolLiteralValue value;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: <Widget>[
        Switch(
          value: value.value,
          onChanged: (newBool) async {
            if (newBool == value.value) return;
            final newValue = BoolLiteralValue(value: newBool, span: value.span);
            await ref.read(workspaceControllerProvider).applyPropertyEdit(
                  uri: documentUri,
                  oldValue: value,
                  newValue: newValue,
                );
          },
        ),
        const SizedBox(width: 8),
        Text(
          value.value ? 'true' : 'false',
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        ),
      ],
    );
  }
}
