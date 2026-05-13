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

    // Positional args, in catalog index order.
    final reverseLookup = <String, int>{
      for (final entry in spec.positionalToProperty.entries)
        entry.value: entry.key,
    };
    final positionalIndices = spec.positionalToProperty.keys.toList()..sort();
    for (final idx in positionalIndices) {
      final propName = spec.positionalToProperty[idx]!;
      final value = node.properties[propName];
      if (value != null) {
        parts.add(PropertySerializer.serialize(value));
      }
    }

    // Named args: properties (non-positional) + child slots. Sorted by name.
    final namedParts = <String, String>{};
    for (final entry in node.properties.entries) {
      if (reverseLookup.containsKey(entry.key)) {
        continue;
      }
      // Skip synthetic positional-opaque keys (visitor generates names
      // like `__positional0` for unmodeled positionals — those round
      // trip via PropertySerializer for opaque types).
      if (entry.key.startsWith('__positional')) {
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
