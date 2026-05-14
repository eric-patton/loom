import '../catalog/widget_catalog.dart';
import '../model/widget_node.dart';
import 'property_serializer.dart';

/// Recursively converts a `ModelNode` to Dart source.
///
/// For `WidgetNode`s, regenerates the constructor call: positional args
/// first (by catalog index), then named arguments alphabetically. For
/// `OpaqueNode`s, returns the captured verbatim source text.
///
/// `const`/`new` keywords and the constructor's own trailing-comma state
/// come from `StyleHints`. Multi-line formatting is not emitted by this
/// serializer; the call site (e.g. list-insert) controls whitespace
/// between arguments.
class WidgetSerializer {
  WidgetSerializer._();

  static String serialize(ModelNode node) => switch (node) {
        final WidgetNode w => _serializeWidget(w),
        final OpaqueNode o => o.sourceText,
        // A `MethodReferenceNode` re-emits as `methodName()`. This
        // assumes the helper already exists in the source — M5 doesn't
        // create helpers via emission. Move-style edits use a byte-copy
        // path (see moveChildEdits) and don't reach the serializer.
        final MethodReferenceNode m => '${m.methodName}()',
      };

  static String _serializeWidget(WidgetNode node) {
    final spec = WidgetCatalog.specFor(node.className);
    if (spec == null) {
      throw ArgumentError(
        'No catalog entry for ${node.className}; cannot serialize',
      );
    }

    final buf = StringBuffer();
    if (node.styleHints.hasConst) {
      buf.write('const ');
    } else if (node.styleHints.hasNew) {
      buf.write('new ');
    }
    buf.write(node.className);
    buf.write('(');

    final parts = <String>[];

    // Positional args: collect from BOTH the catalog (modeled positionals)
    // and from `__positional$i` opaque entries (unmodeled positionals).
    // Both are keyed by their original positional index so we emit them
    // in source order, not grouped by source.
    final reverseLookup = <String, int>{
      for (final entry in spec.positionalToProperty.entries)
        entry.value: entry.key,
    };
    final positionalByIndex = <int, String>{};
    for (final entry in spec.positionalToProperty.entries) {
      final value = node.properties[entry.value];
      if (value != null) {
        positionalByIndex[entry.key] = PropertySerializer.serialize(value);
      }
    }
    for (final entry in node.properties.entries) {
      if (!entry.key.startsWith(kPositionalOpaqueKeyPrefix)) {
        continue;
      }
      final idx = int.tryParse(
        entry.key.substring(kPositionalOpaqueKeyPrefix.length),
      );
      if (idx == null) {
        continue;
      }
      if (positionalByIndex.containsKey(idx)) {
        // Both a catalog-mapped positional and an `__positional$idx`
        // entry claim this index — the visitor never produces this
        // shape (it picks one path per arg), so this can only happen
        // when an external caller hand-builds a `WidgetNode`. Refuse
        // to silently pick one over the other.
        final mapped = spec.positionalToProperty[idx];
        throw ArgumentError(
          'Conflicting positional argument at index $idx on '
          '${node.className}: catalog maps index to "$mapped" and '
          'properties also contains "${entry.key}". Drop one.',
        );
      }
      positionalByIndex[idx] = PropertySerializer.serialize(entry.value);
    }
    final sortedPositional = positionalByIndex.keys.toList()..sort();
    for (final idx in sortedPositional) {
      parts.add(positionalByIndex[idx]!);
    }

    // Named args: properties (non-positional, non-__positional) + child
    // slots. Sorted alphabetically by name.
    final namedParts = <String, String>{};
    for (final entry in node.properties.entries) {
      if (reverseLookup.containsKey(entry.key)) {
        continue;
      }
      if (entry.key.startsWith(kPositionalOpaqueKeyPrefix)) {
        continue;
      }
      namedParts[entry.key] =
          '${entry.key}: ${PropertySerializer.serialize(entry.value)}';
    }
    for (final entry in node.childSlots.entries) {
      final shape = spec.childSlots[entry.key];
      if (shape == ChildSlotShape.list) {
        final inner = entry.value.map(serialize).join(', ');
        namedParts[entry.key] = '${entry.key}: [$inner]';
      } else {
        if (entry.value.isEmpty) {
          continue;
        }
        namedParts[entry.key] = '${entry.key}: ${serialize(entry.value.first)}';
      }
    }
    final sortedNamedKeys = namedParts.keys.toList()..sort();
    for (final key in sortedNamedKeys) {
      parts.add(namedParts[key]!);
    }

    buf.write(parts.join(', '));
    if (node.styleHints.hasTrailingComma && parts.isNotEmpty) {
      buf.write(',');
    }
    buf.write(')');
    return buf.toString();
  }
}
