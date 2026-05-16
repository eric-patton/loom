import '../catalog/pipeline_catalog.dart';
import '../model/node.dart';
import 'constructor_call_serializer.dart';

/// Recursively converts a `ModelNode` (pipeline-tree-positioned) to Dart
/// source. Sibling of `WidgetSerializer` and `RouteSerializer`.
///
/// M6.2 added this as the third domain serializer, written on top of
/// [ConstructorCallSerializer] from the start (extracted alongside this
/// class). Shape mirrors the other two domain serializers exactly.
class PipelineSerializer {
  PipelineSerializer._();

  static String serialize(ModelNode node) => switch (node) {
        final PipelineNode p => _serializePipelineNode(p),
        final OpaqueNode o => o.sourceText,
        final MethodReferenceNode m => '${m.methodName}()',
        WidgetNode() || RouteNode() => throw ArgumentError(
            'PipelineSerializer cannot serialize a non-pipeline modeled node',
          ),
      };

  static String _serializePipelineNode(PipelineNode node) {
    final parentSpec = PipelineCatalog.specFor(node.className);
    if (parentSpec == null) {
      throw ArgumentError(
        'No catalog entry for ${node.className}; cannot serialize',
      );
    }
    final spec = node.namedConstructor == null
        ? parentSpec
        : parentSpec.namedConstructors[node.namedConstructor!];
    if (spec == null) {
      throw ArgumentError(
        'No catalog entry for ${node.className}.${node.namedConstructor}; '
        'cannot serialize',
      );
    }
    return ConstructorCallSerializer.serialize(
      className: node.className,
      namedConstructor: node.namedConstructor,
      properties: node.properties,
      childSlots: node.childSlots,
      styleHints: node.styleHints,
      spec: spec,
      recurse: PipelineSerializer.serialize,
    );
  }
}
