import 'package:flutter/material.dart';

import '../services/kernel_adapter.dart';

/// Read-only badge for any `PropertyValue` the M11 inspector doesn't
/// know how to edit (null, EdgeInsets.all(...), Color(...), enum
/// references, raw opaque source). Shows the value's serialized form
/// so the user can see what's there without being able to mutate it.
class OpaquePropertyReadout extends StatelessWidget {
  const OpaquePropertyReadout({super.key, required this.value});

  final PropertyValue value;

  /// One-line label for the read-only badge. Truncates opaque source
  /// at 40 chars to keep the inspector usable.
  static String labelFor(PropertyValue v) {
    return switch (v) {
      NullLiteralValue() => 'null',
      EdgeInsetsAllValue(amount: final a) => 'EdgeInsets.all($a)',
      ColorValue(argbValue: final argb) =>
        'Color(0x${argb.toRadixString(16).padLeft(8, '0').toUpperCase()})',
      EnumReferenceValue(typeName: final t, memberName: final m) => '$t.$m',
      OpaquePropertyValue(sourceText: final s) =>
        s.length > 40 ? '${s.substring(0, 40)}…' : s,
      StringLiteralValue() ||
      NumLiteralValue() ||
      BoolLiteralValue() =>
        v.toString(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        labelFor(value),
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          fontFamily: 'monospace',
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
