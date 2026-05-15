import '../catalog/catalog_spec.dart';
import '../model/node.dart';
import '../model/property_value.dart';
import '../model/style_hints.dart';
import 'property_serializer.dart';

/// Serializes the constructor-call shape shared by `WidgetNode`,
/// `RouteNode`, and `PipelineNode` (and any future modeled-call node).
///
/// M6.2 extracted this when adding the third domain catalog made the
/// duplication between `WidgetSerializer._serializeWidget` and
/// `RouteSerializer._serializeRouteNode` concrete (rule of three). The
/// per-domain serializers now wrap this helper, supplying:
///   * the node's raw fields (`className`, `properties`, `childSlots`,
///     `styleHints`),
///   * the relevant `CatalogSpec`, and
///   * a `recurse` callback so children of any `ModelNode` subtype route
///     through the correct domain's `serialize`.
///
/// Reduces each per-domain `_serializeXxxNode` from ~100 lines to ~10.
class ConstructorCallSerializer {
  ConstructorCallSerializer._();

  static String serialize({
    required String className,
    required Map<String, PropertyValue> properties,
    required Map<String, List<ModelNode>> childSlots,
    required StyleHints styleHints,
    required CatalogSpec spec,
    required String Function(ModelNode) recurse,
  }) {
    final buf = StringBuffer();
    if (styleHints.hasConst) {
      buf.write('const ');
    } else if (styleHints.hasNew) {
      buf.write('new ');
    }
    buf.write(className);
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
      final value = properties[entry.value];
      if (value != null) {
        positionalByIndex[entry.key] = PropertySerializer.serialize(value);
      }
    }
    for (final entry in properties.entries) {
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
        // Both a catalog-mapped positional and an `__positional$idx` entry
        // claim this index — the visitor never produces this shape (it
        // picks one path per arg), so this can only happen when an
        // external caller hand-builds a modeled node. Refuse to silently
        // pick one over the other.
        final mapped = spec.positionalToProperty[idx];
        throw ArgumentError(
          'Conflicting positional argument at index $idx on '
          '$className: catalog maps index to "$mapped" and '
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
    for (final entry in properties.entries) {
      if (reverseLookup.containsKey(entry.key)) {
        continue;
      }
      if (entry.key.startsWith(kPositionalOpaqueKeyPrefix)) {
        continue;
      }
      namedParts[entry.key] =
          '${entry.key}: ${PropertySerializer.serialize(entry.value)}';
    }
    for (final entry in childSlots.entries) {
      final shape = spec.childSlots[entry.key];
      if (shape == ChildSlotShape.list) {
        final inner = entry.value.map(recurse).join(', ');
        namedParts[entry.key] = '${entry.key}: [$inner]';
      } else {
        if (entry.value.isEmpty) {
          continue;
        }
        namedParts[entry.key] = '${entry.key}: ${recurse(entry.value.first)}';
      }
    }
    final sortedNamedKeys = namedParts.keys.toList()..sort();
    for (final key in sortedNamedKeys) {
      parts.add(namedParts[key]!);
    }

    buf.write(parts.join(', '));
    if (styleHints.hasTrailingComma && parts.isNotEmpty) {
      buf.write(',');
    }
    buf.write(')');
    return buf.toString();
  }
}
