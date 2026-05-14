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

  static RouteSpec? specFor(String className) => _known[className];

  static bool isKnown(String className) => _known.containsKey(className);

  /// Returns the set of class names treated as "route root" candidates
  /// when scanning a compilation unit for `parseRouteTree`. Currently the
  /// catalog's full key set; the parser uses this to decide whether a
  /// top-level variable's initializer is a route tree root or just an
  /// ordinary expression.
  static Set<String> rootClassNames() => _known.keys.toSet();
}
