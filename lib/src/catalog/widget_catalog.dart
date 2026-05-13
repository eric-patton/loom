/// Metadata for the (small) set of widgets M1 actually models.
///
/// The parser consults the catalog for two questions:
///   1. Which named arguments are widget-valued child slots, and what shape
///      is each — `single` (`child:`-like) or `list` (`children:`-like)?
///   2. Which positional arguments map to which model properties (e.g.
///      `Text('hello')` -> property `data`)?
///
/// Widgets not in the catalog will cause the parser to throw in M1. The
/// proper opaque-fallback story lands in M4 (`OpaqueNode`).
enum ChildSlotShape { single, list }

class WidgetSpec {
  const WidgetSpec({
    this.childSlots = const <String, ChildSlotShape>{},
    this.positionalToProperty = const <int, String>{},
  });

  /// Named arguments that hold child widgets, and the shape of each slot.
  /// A `single` slot accepts one widget directly (`child: foo`); a `list`
  /// slot accepts a list literal of widgets (`children: [...]`).
  final Map<String, ChildSlotShape> childSlots;

  /// Maps positional argument index to model property name.
  final Map<int, String> positionalToProperty;
}

class WidgetCatalog {
  WidgetCatalog._();

  static const Map<String, WidgetSpec> _known = <String, WidgetSpec>{
    // Layout primitives.
    'Column': WidgetSpec(
      childSlots: {'children': ChildSlotShape.list},
    ),
    'Row': WidgetSpec(
      childSlots: {'children': ChildSlotShape.list},
    ),
    'Padding': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'Center': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'SizedBox': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'Container': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'Expanded': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),

    // App scaffolding.
    'MaterialApp': WidgetSpec(
      childSlots: {'home': ChildSlotShape.single},
    ),
    'Scaffold': WidgetSpec(
      childSlots: {
        'body': ChildSlotShape.single,
        'appBar': ChildSlotShape.single,
        'floatingActionButton': ChildSlotShape.single,
        'drawer': ChildSlotShape.single,
        'bottomNavigationBar': ChildSlotShape.single,
      },
    ),
    'AppBar': WidgetSpec(
      childSlots: {
        'leading': ChildSlotShape.single,
        'title': ChildSlotShape.single,
        'bottom': ChildSlotShape.single,
        'actions': ChildSlotShape.list,
      },
    ),
    'DefaultTabController': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'TabBar': WidgetSpec(
      childSlots: {'tabs': ChildSlotShape.list},
    ),
    'TabBarView': WidgetSpec(
      childSlots: {'children': ChildSlotShape.list},
    ),
    'Tab': WidgetSpec(
      childSlots: {
        'icon': ChildSlotShape.single,
        'child': ChildSlotShape.single
      },
    ),

    // Leaves and buttons.
    'Text': WidgetSpec(positionalToProperty: <int, String>{0: 'data'}),
    'Icon': WidgetSpec(positionalToProperty: <int, String>{0: 'icon'}),
    'IconButton': WidgetSpec(
      childSlots: {'icon': ChildSlotShape.single},
    ),
    'FloatingActionButton': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
  };

  static WidgetSpec? specFor(String className) => _known[className];

  static bool isKnown(String className) => _known.containsKey(className);
}
