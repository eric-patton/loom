import 'widget_catalog.dart' show ChildSlotShape;

export 'widget_catalog.dart' show ChildSlotShape;

/// Catalog of route-DSL constructors (GoRouter-shaped) the kernel models.
///
/// Same role as `WidgetCatalog` on the widget side: tells the parser which
/// named arguments hold child routes (and what shape), and which positional
/// arguments map to model properties. Anything outside this catalog lands
/// as `RouteOpaqueNode`.
///
/// Initial population covers the three constructors a typical app router
/// uses. Adding more (e.g. `StatefulShellRoute.indexedStack`,
/// `GoRouter.routingConfig`) is a single-line addition.
class RouteSpec {
  const RouteSpec({
    this.childSlots = const <String, ChildSlotShape>{},
    this.positionalToProperty = const <int, String>{},
  });

  /// Named arguments that hold child routes, and the shape of each slot.
  /// All route slots in the current catalog are list-shaped (`routes: [...]`).
  final Map<String, ChildSlotShape> childSlots;

  /// Maps positional argument index to model property name. Empty for the
  /// initial three entries — GoRouter / GoRoute / ShellRoute use named args
  /// for everything that matters.
  final Map<int, String> positionalToProperty;
}

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
