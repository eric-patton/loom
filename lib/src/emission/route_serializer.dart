import '../catalog/route_catalog.dart';
import '../model/node.dart';
import 'property_serializer.dart';

/// Recursively converts a `ModelNode` (route-tree-positioned) to Dart
/// source. Sibling of `WidgetSerializer`; extracted from the inlined
/// route-edit-planner helper in M6.1 Phase 3.
///
/// For `RouteNode`s, regenerates the constructor call: positional args
/// first (by catalog index), then named arguments alphabetically. For
/// `OpaqueNode`s, returns the captured verbatim source text. For
/// `MethodReferenceNode`s, emits `methodName()` — assuming the helper
/// already exists in source.
///
/// `WidgetNode` is unreachable in practice (the route visitor never
/// produces one) but lives in the sealed `ModelNode` hierarchy since
/// M6.1 Phase 1, so the switch handles it with an explicit throw.
class RouteSerializer {
  RouteSerializer._();

  static String serialize(ModelNode node) => switch (node) {
        final RouteNode r => _serializeRouteNode(r),
        final OpaqueNode o => o.sourceText,
        final MethodReferenceNode m => '${m.methodName}()',
        WidgetNode() => throw ArgumentError(
            'RouteSerializer cannot serialize a WidgetNode',
          ),
      };

  static String _serializeRouteNode(RouteNode node) {
    final spec = RouteCatalog.specFor(node.className);
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
        // entry claim this index — the visitor never produces this shape
        // (it picks one path per arg), so this can only happen when an
        // external caller hand-builds a `RouteNode`. Refuse to silently
        // pick one over the other.
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
