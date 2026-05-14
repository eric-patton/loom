// Metadata for the set of widgets the kernel models.
//
// The catalog answers two parser questions per node:
//   1. Which named arguments are widget-valued child slots, and what shape?
//   2. Which positional arguments map to which model properties?
//
// Widgets not in the catalog land as `OpaqueNode` (M4).
//
// `WidgetSpec` is a typedef of the language-general `CatalogSpec` (extracted
// M6.1 Phase 2 — the spec shape is shared with `RouteSpec` and any future
// domain catalog).
import 'catalog_spec.dart';

export 'catalog_spec.dart' show CatalogSpec, ChildSlotShape;

typedef WidgetSpec = CatalogSpec;

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
    'GestureDetector': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'InkWell': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'Material': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'SafeArea': WidgetSpec(
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
