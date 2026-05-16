// Catalog of route-DSL constructors (GoRouter-shaped) the kernel models.
// `RouteSpec` is a typedef of the shared `CatalogSpec` (M6.1 Phase 2).
import 'catalog_spec.dart';

export 'catalog_spec.dart' show CatalogSpec, ChildSlotShape;

typedef RouteSpec = CatalogSpec;

class RouteCatalog {
  RouteCatalog._();

  static const Map<String, RouteSpec> _known = <String, RouteSpec>{
    'GoRouter': RouteSpec(
      childSlots: {'routes': ChildSlotShape.list},
    ),
    'GoRoute': RouteSpec(
      childSlots: {'routes': ChildSlotShape.list},
    ),
    'ShellRoute': RouteSpec(
      childSlots: {'routes': ChildSlotShape.list},
    ),
  };

  /// Class names that can appear as the **root** of a route tree.
  /// `GoRoute` and `ShellRoute` are tree-internal — they nest inside a
  /// `GoRouter`'s `routes:` list, never standing alone as the config root.
  /// The parser uses this to discriminate "is this top-level variable or
  /// class-field initializer a route tree?" from "is it some other
  /// catalog-known constructor invocation?"
  static const Set<String> _treeRootClassNames = <String>{'GoRouter'};

  static RouteSpec? specFor(String className) => _known[className];

  static bool isKnown(String className) => _known.containsKey(className);

  /// Returns the set of class names treated as route-tree roots when
  /// scanning a compilation unit for `parseRouteTree`. The visitor still
  /// recognizes the full catalog for in-tree nodes; this set is narrower
  /// because non-root catalog entries can't anchor a parseable tree.
  static Set<String> rootClassNames() => _treeRootClassNames;
}
