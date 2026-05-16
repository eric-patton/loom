import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/kernel_adapter.dart';
import 'bool_property_editor.dart';
import 'num_property_editor.dart';
import 'opaque_property_readout.dart';
import 'string_property_editor.dart';

/// Dispatches one property-editor row by [propertyValue] runtime type:
///
///   - `StringLiteralValue` → [StringPropertyEditor]
///   - `NumLiteralValue`     → [NumPropertyEditor]
///   - `BoolLiteralValue`    → [BoolPropertyEditor]
///   - everything else       → [OpaquePropertyReadout]
///
/// The label text + spacing are owned here so each editor only needs
/// to draw its input control.
class PropertyEditorRouter extends ConsumerWidget {
  const PropertyEditorRouter({
    super.key,
    required this.documentUri,
    required this.nodePath,
    required this.propertyName,
    required this.propertyValue,
  });

  final String documentUri;
  final NodePath nodePath;
  final String propertyName;
  final PropertyValue propertyValue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final value = propertyValue;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            propertyName,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          // The `ValueKey(value.span)` rebuilds the editor whenever the
          // underlying span changes (i.e. after a re-parse from a save),
          // forcing a fresh TextEditingController and dropping stale
          // closures over the previous span.
          switch (value) {
            StringLiteralValue() => StringPropertyEditor(
                key: ValueKey<Object>(
                  ('string', value.span.offset, value.span.length),
                ),
                documentUri: documentUri,
                propertyName: propertyName,
                value: value,
              ),
            NumLiteralValue() => NumPropertyEditor(
                key: ValueKey<Object>(
                  ('num', value.span.offset, value.span.length),
                ),
                documentUri: documentUri,
                propertyName: propertyName,
                value: value,
              ),
            BoolLiteralValue() => BoolPropertyEditor(
                key: ValueKey<Object>(
                  ('bool', value.span.offset, value.span.length),
                ),
                documentUri: documentUri,
                propertyName: propertyName,
                value: value,
              ),
            NullLiteralValue() ||
            EdgeInsetsAllValue() ||
            ColorValue() ||
            EnumReferenceValue() ||
            OpaquePropertyValue() =>
              OpaquePropertyReadout(value: value),
          },
        ],
      ),
    );
  }
}
