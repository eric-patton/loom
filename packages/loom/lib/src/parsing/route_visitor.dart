import '../catalog/route_catalog.dart';
import '../model/list_slot_style.dart';
import '../model/node.dart';
import '../model/property_value.dart';
import '../model/source_span.dart';
import '../model/style_hints.dart';
import 'base_visitor.dart';

/// Walks a route expression and produces a `ModelNode` (a `RouteNode` for
/// modeled catalog constructor calls, otherwise `OpaqueNode` or
/// `MethodReferenceNode`).
///
/// M6.1 Phase 2: thin shim over [BaseVisitor]. Only two domain hooks
/// needed — the route DSL doesn't have widget-side property kinds like
/// `EdgeInsets.all(N)` or `Color(0x…)`, so the default
/// `customConstructorPropertyValue` (always null) is correct.
class RouteVisitor extends BaseVisitor {
  RouteVisitor(super.source, {super.classMethods});

  @override
  CatalogSpec? specFor(String className) => RouteCatalog.specFor(className);

  @override
  ModelNode buildModeledNode({
    required String className,
    required String? namedConstructor,
    required Map<String, PropertyValue> properties,
    required Map<String, List<ModelNode>> childSlots,
    required Map<String, ListSlotStyle> childSlotStyles,
    required SourceSpan sourceSpan,
    required StyleHints styleHints,
  }) {
    return RouteNode(
      className: className,
      namedConstructor: namedConstructor,
      properties: properties,
      childSlots: childSlots,
      childSlotStyles: childSlotStyles,
      sourceSpan: sourceSpan,
      styleHints: styleHints,
    );
  }
}
