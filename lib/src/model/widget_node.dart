import 'property_value.dart';
import 'source_span.dart';
import 'style_hints.dart';

/// A node in the visual model. One per `InstanceCreationExpression` in the
/// source — i.e. one per widget constructor call.
///
/// Stores enough information to render an indented tree (M1), to emit
/// minimal-diff `SourceEdit`s for property/child changes (M2/M3), and to
/// compare against a re-parsed model under the M2 round-trip property test
/// (Settled Decisions Q3, DEVLOG.md).
class WidgetNode {
  WidgetNode({
    required this.className,
    required Map<String, PropertyValue> properties,
    required List<WidgetNode> children,
    required this.sourceSpan,
    required this.styleHints,
  })  : properties = Map.unmodifiable(properties),
        children = List.unmodifiable(children);

  /// Class name of the constructor invoked — e.g. `'Column'`.
  final String className;

  /// Modeled literal properties keyed by the named-argument label they came
  /// from (e.g. `'padding'`). Children are NOT in this map; they live in
  /// `children`.
  final Map<String, PropertyValue> properties;

  /// Child widgets, in source order. Both `child:` (single-shaped) and
  /// `children:` (list-shaped) parameters land here — the catalog tells the
  /// parser which named argument feeds this list. Renderers that need to
  /// know the original argument shape consult the catalog with `className`.
  final List<WidgetNode> children;

  /// Byte range of the constructor call (including any leading `const`/`new`
  /// keyword and the trailing `)`).
  final SourceSpan sourceSpan;

  final StyleHints styleHints;

  @override
  String toString() =>
      'WidgetNode($className @${sourceSpan.offset}+${sourceSpan.length}, '
      '${properties.length} prop(s), ${children.length} child(ren))';
}

/// Public root of the visual model. Thin wrapper around the root `WidgetNode`;
/// later milestones will add fields here (method references in M5, etc.).
class WidgetTreeModel {
  const WidgetTreeModel({required this.root});

  final WidgetNode root;

  @override
  String toString() => 'WidgetTreeModel(rootClass=${root.className})';
}
