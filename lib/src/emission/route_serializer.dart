import '../catalog/route_catalog.dart';
import '../model/node.dart';
import 'constructor_call_serializer.dart';

/// Recursively converts a `ModelNode` (route-tree-positioned) to Dart
/// source. Sibling of `WidgetSerializer`.
///
/// M6.2 thinned this to per-domain dispatch + a per-domain catalog
/// lookup; the actual constructor-call serialization lives in the
/// shared [ConstructorCallSerializer].
class RouteSerializer {
  RouteSerializer._();

  static String serialize(ModelNode node) => switch (node) {
        final RouteNode r => _serializeRouteNode(r),
        final OpaqueNode o => o.sourceText,
        final MethodReferenceNode m => '${m.methodName}()',
        WidgetNode() || PipelineNode() => throw ArgumentError(
            'RouteSerializer cannot serialize a non-route modeled node',
          ),
      };

  static String _serializeRouteNode(RouteNode node) {
    final spec = RouteCatalog.specFor(node.className);
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
      recurse: RouteSerializer.serialize,
    );
  }
}
