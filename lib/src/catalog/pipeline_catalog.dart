// Catalog of pipeline-DSL constructors. M6.2 introduced this synthetic
// catalog as a third domain consumer of the unified kernel — invented for
// the demo, but representative of where the OutSystems-style trajectory
// leads (workflows / business-logic flows as declarative constructor trees).
//
// `PipelineSpec` is a typedef of the shared `CatalogSpec` (M6.1 Phase 2).
import 'catalog_spec.dart';

export 'catalog_spec.dart' show CatalogSpec, ChildSlotShape;

typedef PipelineSpec = CatalogSpec;

class PipelineCatalog {
  PipelineCatalog._();

  static const Map<String, PipelineSpec> _known = <String, PipelineSpec>{
    'Pipeline': PipelineSpec(
      childSlots: {'steps': ChildSlotShape.list},
    ),
    'Branch': PipelineSpec(
      childSlots: {
        'onTrue': ChildSlotShape.list,
        'onFalse': ChildSlotShape.list,
      },
    ),
    // Leaves — properties only, no child slots.
    'ValidateInput': PipelineSpec(),
    'Transform': PipelineSpec(),
    'SaveToDatabase': PipelineSpec(),
    'SendEmail': PipelineSpec(),
    'LogError': PipelineSpec(),
    'LogInfo': PipelineSpec(),
  };

  /// Class names that can anchor a pipeline tree. Only `Pipeline` —
  /// every other catalog entry is tree-internal.
  static const Set<String> _treeRootClassNames = <String>{'Pipeline'};

  static PipelineSpec? specFor(String className) => _known[className];

  static bool isKnown(String className) => _known.containsKey(className);

  static Set<String> rootClassNames() => _treeRootClassNames;
}
