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
    'ElevatedButton': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'TextButton': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'OutlinedButton': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'FilledButton': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'Placeholder': WidgetSpec(),
    'UiKitView': WidgetSpec(),
    'AndroidView': WidgetSpec(),
    'HtmlElementView': WidgetSpec(),

    // ---------------- Phase 3 catalog expansion ----------------
    // Drawn from the opaque-root diagnostic against Flutter SDK +
    // flutter-packages: every framework class that the diagnostic saw
    // ≥2 times as a build()-return root, plus a handful of obvious
    // companions (Wrap, Hero, Card, Align, etc.) used to compose those.

    // Layout: stacks, lists, grids, sliver-shaped containers.
    'Stack': WidgetSpec(
      childSlots: {'children': ChildSlotShape.list},
    ),
    'IndexedStack': WidgetSpec(
      childSlots: {'children': ChildSlotShape.list},
    ),
    'Wrap': WidgetSpec(
      childSlots: {'children': ChildSlotShape.list},
    ),
    'Flow': WidgetSpec(
      childSlots: {'children': ChildSlotShape.list},
    ),
    'ListView': WidgetSpec(
      childSlots: {'children': ChildSlotShape.list},
    ),
    'GridView': WidgetSpec(
      childSlots: {'children': ChildSlotShape.list},
    ),
    'CustomScrollView': WidgetSpec(
      childSlots: {'slivers': ChildSlotShape.list},
    ),
    'Positioned': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),

    // Single-child layout wrappers (clipping, sizing, transformations).
    'Align': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'AspectRatio': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'ConstrainedBox': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'FittedBox': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'FractionallySizedBox': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'OverflowBox': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'Transform': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'ClipRect': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'ClipRRect': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'ClipOval': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'ClipPath': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'Opacity': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'Visibility': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'Offstage': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'AbsorbPointer': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'IgnorePointer': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'DecoratedBox': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'Card': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'Hero': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'KeepAlive': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),

    // Animation wrappers — the implicit-animation family. All take a
    // single `child:` and drive properties around it.
    'AnimatedContainer': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'AnimatedPadding': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'AnimatedAlign': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'AnimatedOpacity': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'AnimatedSize': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'AnimatedPositioned': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'AnimatedSwitcher': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    // Builder-shaped animation widgets — `builder:` is a callback so it
    // stays opaque; the optional `child:` is real and gets modeled.
    'AnimatedBuilder': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'DualTransitionBuilder': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'FutureBuilder': WidgetSpec(),
    'StreamBuilder': WidgetSpec(),
    'LayoutBuilder': WidgetSpec(),

    // Painting / decoration.
    'CustomPaint': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),

    // Accessibility and semantics.
    'Semantics': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'MergeSemantics': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'ExcludeSemantics': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'BlockSemantics': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),

    // Input / focus / pointer / shortcuts.
    'Focus': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'FocusScope': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'FocusableActionDetector': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'Listener': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'MouseRegion': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'TapRegion': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'NotificationListener': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'Actions': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'Shortcuts': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),

    // Inherited-widget scopes that surround a child subtree.
    'Directionality': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'MediaQuery': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'Localizations': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'Theme': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'DefaultTextStyle': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'IconTheme': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'ScrollConfiguration': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'RootRestorationScope': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'UnmanagedRestorationScope': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),

    // Cupertino app shell + navigation primitives.
    'CupertinoApp': WidgetSpec(
      childSlots: {'home': ChildSlotShape.single},
    ),
    'CupertinoPageScaffold': WidgetSpec(
      childSlots: {
        'child': ChildSlotShape.single,
        'navigationBar': ChildSlotShape.single,
      },
    ),
    'CupertinoTabScaffold': WidgetSpec(),
    // Form composition.
    'Form': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
  };

  static WidgetSpec? specFor(String className) => _known[className];

  static bool isKnown(String className) => _known.containsKey(className);
}
