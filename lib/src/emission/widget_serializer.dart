import '../catalog/widget_catalog.dart';
import '../model/widget_node.dart';
import 'property_serializer.dart';

/// Recursively converts a `WidgetNode` to Dart source. Mirrors
/// `PropertySerializer` but for widget constructor calls.
///
/// Used by M3 structural edits when inserting a new child — the inserted
/// widget needs a source representation that re-parses to the same node.
///
/// Argument-order convention: positional first (by catalog index), then
/// named arguments alphabetically. The exact order isn't observable
/// through the model (properties + child slots are maps), but a fixed
/// order keeps emitted source deterministic.
///
/// `const`/`new` keywords and the constructor's own trailing-comma state
/// come from `StyleHints`. Multi-line formatting is not emitted by this
/// serializer; the call site (e.g. list-insert) controls whitespace
/// between arguments.
class WidgetSerializer {
  WidgetSerializer._();

  static String serialize(WidgetNode node) {
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
