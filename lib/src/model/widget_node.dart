import 'property_value.dart';
import 'source_span.dart';
import 'style_hints.dart';

/// A node in the visual model. One per constructor call in the source.
///
/// Stores enough information to render an indented tree (M1), to emit
/// minimal-diff `SourceEdit`s for property/child changes (M2/M3), and to
/// compare against a re-parsed model under the M2 round-trip property test
/// (Settled Decisions Q3, DEVLOG.md).
class WidgetNode {
  WidgetNode({
    required this.className,
    required Map<String, PropertyValue> properties,
    required Map<String, List<WidgetNode>> childSlots,
    required this.sourceSpan,
    required this.styleHints,
  })  : properties = Map.unmodifiable(properties),
        childSlots = Map.unmodifiable({
          for (final entry in childSlots.entries)
            entry.key: List<WidgetNode>.unmodifiable(entry.value),
        });

  /// Class name of the constructor invoked — e.g. `'Column'`.
  final String className;

  /// Modeled literal properties keyed by the named-argument label they came
  /// from. Children are NOT in this map; they live in `childSlots`.
  final Map<String, PropertyValue> properties;

  /// Widget-valued named arguments grouped by their slot name. A
  /// list-shaped slot (e.g. `Column.children`) holds the elements in source
  /// order; a single-shaped slot (e.g. `Padding.child`) holds a one-element
  /// list. The catalog declares which slots a widget has and which shape
  /// each takes — see `lib/src/catalog/widget_catalog.dart`.
  final Map<String, List<WidgetNode>> childSlots;

  /// Byte range of the constructor call (including any leading
  /// `const`/`new` keyword and the trailing `)`).
  final SourceSpan sourceSpan;

  final StyleHints styleHints;

  @override
  String toString() {
    final totalChildren = childSlots.values.fold<int>(
      0,
      (sum, list) => sum + list.length,
    );
    return 'WidgetNode($className @${sourceSpan.offset}+${sourceSpan.length}, '
        '${properties.length} prop(s), ${childSlots.length} slot(s), '
        '$totalChildren child(ren))';
  }
}

/// Public root of the visual model. Thin wrapper around the root `WidgetNode`;
/// later milestones will add fields here (method references in M5, etc.).
class WidgetTreeModel {
  const WidgetTreeModel({required this.root});

  final WidgetNode root;

  @override
  String toString() => 'WidgetTreeModel(rootClass=${root.className})';
}
