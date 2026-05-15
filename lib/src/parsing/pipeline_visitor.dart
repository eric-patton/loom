import '../catalog/pipeline_catalog.dart';
import '../model/list_slot_style.dart';
import '../model/node.dart';
import '../model/property_value.dart';
import '../model/source_span.dart';
import '../model/style_hints.dart';
import 'base_visitor.dart';

/// Walks a pipeline-DSL expression and produces a `ModelNode` (a
/// `PipelineNode` for modeled catalog constructor calls, otherwise
/// `OpaqueNode` or `MethodReferenceNode`).
///
/// M6.2 first third-domain consumer of [BaseVisitor]. Two domain hooks,
/// no special property recognition — pipeline literals are all standard
/// strings / numbers / booleans / nulls / enum-refs.
class PipelineVisitor extends BaseVisitor {
  PipelineVisitor(super.source, {super.classMethods});

  @override
  CatalogSpec? specFor(String className) => PipelineCatalog.specFor(className);

  @override
  ModelNode buildModeledNode({
    required String className,
    required Map<String, PropertyValue> properties,
    required Map<String, List<ModelNode>> childSlots,
    required Map<String, ListSlotStyle> childSlotStyles,
    required SourceSpan sourceSpan,
    required StyleHints styleHints,
  }) {
    return PipelineNode(
      className: className,
      properties: properties,
      childSlots: childSlots,
      childSlotStyles: childSlotStyles,
      sourceSpan: sourceSpan,
      styleHints: styleHints,
    );
  }
}
