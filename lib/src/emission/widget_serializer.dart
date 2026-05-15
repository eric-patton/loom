import '../catalog/widget_catalog.dart';
import '../model/node.dart';
import 'constructor_call_serializer.dart';

/// Recursively converts a `ModelNode` (widget-tree-positioned) to Dart
/// source.
///
/// M6.2 thinned this to per-domain dispatch + a per-domain catalog
/// lookup; the actual constructor-call serialization lives in the
/// shared [ConstructorCallSerializer]. `const`/`new` keywords and
/// trailing-comma state come from `StyleHints` (preserved by the
/// visitor). Multi-line formatting is not emitted here; the call site
/// (e.g. list-insert) controls whitespace between arguments.
class WidgetSerializer {
  WidgetSerializer._();

  static String serialize(ModelNode node) => switch (node) {
        final WidgetNode w => _serializeWidget(w),
        final OpaqueNode o => o.sourceText,
        // A `MethodReferenceNode` re-emits as `methodName()`. This assumes
        // the helper already exists in the source — M5 doesn't create
        // helpers via emission. Move-style edits use a byte-copy path
        // (see moveChildEdits) and don't reach the serializer.
        final MethodReferenceNode m => '${m.methodName}()',
        // M6.1+: `ModelNode` is sealed across all domain catalogs. The
        // widget serializer never receives a non-widget modeled node in
        // practice (the widget visitor never produces them), but the
        // sealed type includes them, so we throw to make the invariant
        // explicit.
        RouteNode() || PipelineNode() => throw ArgumentError(
            'WidgetSerializer cannot serialize a non-widget modeled node',
          ),
      };

  static String _serializeWidget(WidgetNode node) {
    final spec = WidgetCatalog.specFor(node.className);
    if (spec == null) {
      throw ArgumentError(
        'No catalog entry for ${node.className}; cannot serialize',
      );
    }
    return ConstructorCallSerializer.serialize(
      className: node.className,
      properties: node.properties,
      childSlots: node.childSlots,
      styleHints: node.styleHints,
      spec: spec,
      recurse: WidgetSerializer.serialize,
    );
  }
}
