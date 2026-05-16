// Shared catalog primitives used by both the widget and route catalogs
// (and any future domain catalog). M6.1 Phase 2 promoted these out of
// `widget_catalog.dart` once a second consumer (`route_catalog.dart`)
// proved they're domain-agnostic.

/// Shape of a named child slot in a catalog entry. A `single` slot accepts
/// one node directly (`child: foo`); a `list` slot accepts a list literal
/// of nodes (`children: [...]` or `routes: [...]`).
enum ChildSlotShape { single, list }

/// Per-class metadata the parser consults when walking a catalog-known
/// constructor invocation.
///
/// The parser asks the catalog two questions per call:
///   1. Which named arguments are tree-valued child slots, and what shape
///      is each (`single` or `list`)?
///   2. Which positional arguments map to which model properties (e.g.
///      `Text('hello')` -> property `data`)?
///
/// Both `WidgetSpec` and `RouteSpec` are now typedef aliases of this
/// class — they were structurally identical from the start, and the
/// M6.0 build-alongside work confirmed nothing forces them to diverge.
/// New catalogs (test framework, Drift, etc.) reuse this same shape.
class CatalogSpec {
  const CatalogSpec({
    this.childSlots = const <String, ChildSlotShape>{},
    this.positionalToProperty = const <int, String>{},
    this.namedConstructors = const <String, CatalogSpec>{},
  });

  /// Named arguments that hold child nodes, and the shape of each slot.
  final Map<String, ChildSlotShape> childSlots;

  /// Maps positional argument index to model property name.
  final Map<int, String> positionalToProperty;

  /// Per-named-constructor sub-specs. A call to `Class.foo(...)` looks up
  /// the parent class's spec, then consults `namedConstructors['foo']`.
  /// Each sub-spec is itself a full `CatalogSpec` — named constructors
  /// typically have a different argument shape than the unnamed
  /// constructor (e.g. `MaterialApp.router` takes `routerConfig:` instead
  /// of `home:`). Empty by default; only catalogs that explicitly model
  /// named-constructor variants populate this map.
  final Map<String, CatalogSpec> namedConstructors;
}
