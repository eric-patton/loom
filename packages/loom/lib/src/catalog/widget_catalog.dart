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
      namedConstructors: {
        // All SizedBox named constructors take an optional `child:` Widget.
        // They differ from the unnamed constructor in how they derive width/
        // height (from a Size, by expanding to parent, by collapsing to 0,
        // etc.) but the slot shape is identical.
        'expand': WidgetSpec(
          childSlots: {'child': ChildSlotShape.single},
        ),
        'shrink': WidgetSpec(
          childSlots: {'child': ChildSlotShape.single},
        ),
        'square': WidgetSpec(
          childSlots: {'child': ChildSlotShape.single},
        ),
        'fromSize': WidgetSpec(
          childSlots: {'child': ChildSlotShape.single},
        ),
      },
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
      namedConstructors: {
        // `MaterialApp.router(...)` is the GoRouter-canonical app shell.
        // It takes `routerConfig:` / `routerDelegate:` / etc. instead of
        // `home:` — no widget-valued slots that the kernel models. The
        // entry exists so the parser classifies the call as a `WidgetNode`
        // (modeled root) rather than `OpaqueNode`.
        'router': WidgetSpec(),
      },
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
    'Text': WidgetSpec(
      positionalToProperty: <int, String>{0: 'data'},
      namedConstructors: {
        // `Text.rich(textSpan)` takes an `InlineSpan` (not a Widget) as
        // its first positional. The kernel can recognize it but the
        // textSpan stays as an opaque property.
        'rich': WidgetSpec(),
      },
    ),
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
      namedConstructors: {
        // `ListView.builder` / `.separated` / `.custom` use builder
        // callbacks (`itemBuilder:`, `separatorBuilder:`, `childrenDelegate:`)
        // which the kernel models opaquely — no `children:` slot to wire up.
        'builder': WidgetSpec(),
        'separated': WidgetSpec(),
        'custom': WidgetSpec(),
      },
    ),
    'GridView': WidgetSpec(
      childSlots: {'children': ChildSlotShape.list},
      namedConstructors: {
        // `.count` and `.extent` keep the `children:` list; `.builder`
        // and `.custom` use builder callbacks.
        'count': WidgetSpec(
          childSlots: {'children': ChildSlotShape.list},
        ),
        'extent': WidgetSpec(
          childSlots: {'children': ChildSlotShape.list},
        ),
        'builder': WidgetSpec(),
        'custom': WidgetSpec(),
      },
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
      namedConstructors: {
        // `.merge` wraps a child with merged text-style overrides.
        'merge': WidgetSpec(
          childSlots: {'child': ChildSlotShape.single},
        ),
      },
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

    // ---------------- Phase 6 catalog expansion ----------------
    // Targeted at the UI editor's tree-view: every Sliver inside
    // `CustomScrollView.slivers` used to land opaque, dialogs/sheets
    // were unmodeled, Material 3 navigation was unmodeled. These entries
    // close those gaps so the editor can show structural shape for the
    // widgets users actually compose in real apps.

    // Sliver family — children of `CustomScrollView.slivers`.
    'SliverList': WidgetSpec(
      // `.list` / `.builder` / `.separated` named constructors all use
      // delegate callbacks (`itemBuilder:`, `separatorBuilder:`) which
      // the kernel models opaquely. The base constructor takes
      // `delegate: SliverChildDelegate` which is also opaque, but
      // recognizing the type as a Sliver still gets us out of opaque
      // root territory and lets the editor render a placeholder.
      namedConstructors: {
        'builder': WidgetSpec(),
        'separated': WidgetSpec(),
        'list': WidgetSpec(),
      },
    ),
    'SliverGrid': WidgetSpec(
      namedConstructors: {
        'builder': WidgetSpec(),
        'count': WidgetSpec(
          childSlots: {'children': ChildSlotShape.list},
        ),
        'extent': WidgetSpec(
          childSlots: {'children': ChildSlotShape.list},
        ),
      },
    ),
    'SliverPadding': WidgetSpec(
      childSlots: {'sliver': ChildSlotShape.single},
    ),
    'SliverAppBar': WidgetSpec(
      childSlots: {
        'leading': ChildSlotShape.single,
        'title': ChildSlotShape.single,
        'flexibleSpace': ChildSlotShape.single,
        'bottom': ChildSlotShape.single,
        'actions': ChildSlotShape.list,
      },
      namedConstructors: {
        'medium': WidgetSpec(
          childSlots: {
            'leading': ChildSlotShape.single,
            'title': ChildSlotShape.single,
            'flexibleSpace': ChildSlotShape.single,
            'bottom': ChildSlotShape.single,
            'actions': ChildSlotShape.list,
          },
        ),
        'large': WidgetSpec(
          childSlots: {
            'leading': ChildSlotShape.single,
            'title': ChildSlotShape.single,
            'flexibleSpace': ChildSlotShape.single,
            'bottom': ChildSlotShape.single,
            'actions': ChildSlotShape.list,
          },
        ),
      },
    ),
    'SliverFillRemaining': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'SliverFillViewport': WidgetSpec(),
    'SliverToBoxAdapter': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'SliverPersistentHeader': WidgetSpec(),
    'SliverOpacity': WidgetSpec(
      childSlots: {'sliver': ChildSlotShape.single},
    ),
    'SliverVisibility': WidgetSpec(
      childSlots: {'sliver': ChildSlotShape.single},
    ),
    'SliverSafeArea': WidgetSpec(
      childSlots: {'sliver': ChildSlotShape.single},
    ),
    'SliverAnimatedList': WidgetSpec(),

    // Dialogs and bottom sheets — wrapper widgets commonly composed in
    // showDialog / showModalBottomSheet builder bodies.
    'Dialog': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
      namedConstructors: {
        'fullscreen': WidgetSpec(
          childSlots: {'child': ChildSlotShape.single},
        ),
      },
    ),
    'AlertDialog': WidgetSpec(
      childSlots: {
        'icon': ChildSlotShape.single,
        'title': ChildSlotShape.single,
        'content': ChildSlotShape.single,
        'actions': ChildSlotShape.list,
      },
    ),
    'SimpleDialog': WidgetSpec(
      childSlots: {
        'title': ChildSlotShape.single,
        'children': ChildSlotShape.list,
      },
    ),
    'SimpleDialogOption': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'BottomSheet': WidgetSpec(),
    'CupertinoAlertDialog': WidgetSpec(
      childSlots: {
        'title': ChildSlotShape.single,
        'content': ChildSlotShape.single,
        'actions': ChildSlotShape.list,
      },
    ),
    'CupertinoActionSheet': WidgetSpec(
      childSlots: {
        'title': ChildSlotShape.single,
        'message': ChildSlotShape.single,
        'cancelButton': ChildSlotShape.single,
        'actions': ChildSlotShape.list,
      },
    ),

    // Material 3 navigation primitives.
    'NavigationBar': WidgetSpec(
      childSlots: {'destinations': ChildSlotShape.list},
    ),
    'NavigationDestination': WidgetSpec(
      childSlots: {
        'icon': ChildSlotShape.single,
        'selectedIcon': ChildSlotShape.single,
      },
    ),
    'NavigationRail': WidgetSpec(
      childSlots: {
        'leading': ChildSlotShape.single,
        'trailing': ChildSlotShape.single,
        'destinations': ChildSlotShape.list,
      },
    ),
    'NavigationRailDestination': WidgetSpec(
      childSlots: {
        'icon': ChildSlotShape.single,
        'selectedIcon': ChildSlotShape.single,
        'label': ChildSlotShape.single,
      },
    ),
    'NavigationDrawer': WidgetSpec(
      childSlots: {'children': ChildSlotShape.list},
    ),
    'NavigationDrawerDestination': WidgetSpec(
      childSlots: {
        'icon': ChildSlotShape.single,
        'selectedIcon': ChildSlotShape.single,
        'label': ChildSlotShape.single,
      },
    ),
    'BottomNavigationBar': WidgetSpec(),
    'BottomNavigationBarItem': WidgetSpec(
      childSlots: {
        'icon': ChildSlotShape.single,
        'activeIcon': ChildSlotShape.single,
      },
    ),
    'Drawer': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'DrawerHeader': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'UserAccountsDrawerHeader': WidgetSpec(
      childSlots: {
        'currentAccountPicture': ChildSlotShape.single,
        'otherAccountsPictures': ChildSlotShape.list,
      },
    ),

    // Decoration / effects wrappers.
    'BackdropFilter': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'RepaintBoundary': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'RotatedBox': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'Banner': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'PhysicalModel': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'PhysicalShape': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'ColorFiltered': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'ImageFiltered': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'ShaderMask': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'Tooltip': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'Badge': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
      namedConstructors: {
        'count': WidgetSpec(
          childSlots: {'child': ChildSlotShape.single},
        ),
      },
    ),

    // Builder family — callbacks are opaque, but recognizing the
    // type stops the call from being a fully opaque root.
    'Builder': WidgetSpec(),
    'ValueListenableBuilder': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'ListenableBuilder': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'RestorableValueListenableBuilder': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'SelectableText': WidgetSpec(
      positionalToProperty: <int, String>{0: 'data'},
      namedConstructors: {
        'rich': WidgetSpec(),
      },
    ),
    'RichText': WidgetSpec(),

    // Chip family.
    'Chip': WidgetSpec(
      childSlots: {
        'avatar': ChildSlotShape.single,
        'label': ChildSlotShape.single,
        'deleteIcon': ChildSlotShape.single,
      },
    ),
    'ActionChip': WidgetSpec(
      childSlots: {
        'avatar': ChildSlotShape.single,
        'label': ChildSlotShape.single,
      },
    ),
    'ChoiceChip': WidgetSpec(
      childSlots: {
        'avatar': ChildSlotShape.single,
        'label': ChildSlotShape.single,
      },
    ),
    'FilterChip': WidgetSpec(
      childSlots: {
        'avatar': ChildSlotShape.single,
        'label': ChildSlotShape.single,
      },
    ),
    'InputChip': WidgetSpec(
      childSlots: {
        'avatar': ChildSlotShape.single,
        'label': ChildSlotShape.single,
        'deleteIcon': ChildSlotShape.single,
      },
    ),
    'RawChip': WidgetSpec(
      childSlots: {
        'avatar': ChildSlotShape.single,
        'label': ChildSlotShape.single,
        'deleteIcon': ChildSlotShape.single,
      },
    ),

    // Misc commonly-seen Material widgets.
    'ListTile': WidgetSpec(
      childSlots: {
        'leading': ChildSlotShape.single,
        'title': ChildSlotShape.single,
        'subtitle': ChildSlotShape.single,
        'trailing': ChildSlotShape.single,
      },
    ),
    'CheckboxListTile': WidgetSpec(
      childSlots: {
        'secondary': ChildSlotShape.single,
        'title': ChildSlotShape.single,
        'subtitle': ChildSlotShape.single,
      },
    ),
    'RadioListTile': WidgetSpec(
      childSlots: {
        'secondary': ChildSlotShape.single,
        'title': ChildSlotShape.single,
        'subtitle': ChildSlotShape.single,
      },
    ),
    'SwitchListTile': WidgetSpec(
      childSlots: {
        'secondary': ChildSlotShape.single,
        'title': ChildSlotShape.single,
        'subtitle': ChildSlotShape.single,
      },
    ),
    'ExpansionTile': WidgetSpec(
      childSlots: {
        'leading': ChildSlotShape.single,
        'title': ChildSlotShape.single,
        'subtitle': ChildSlotShape.single,
        'trailing': ChildSlotShape.single,
        'children': ChildSlotShape.list,
      },
    ),
    'ExpansionPanelList': WidgetSpec(
      childSlots: {'children': ChildSlotShape.list},
      namedConstructors: {
        'radio': WidgetSpec(
          childSlots: {'children': ChildSlotShape.list},
        ),
      },
    ),
    'TextField': WidgetSpec(),
    'TextFormField': WidgetSpec(),
    'CupertinoTextField': WidgetSpec(),
    'PopupMenuButton': WidgetSpec(
      childSlots: {
        'icon': ChildSlotShape.single,
        'child': ChildSlotShape.single,
      },
    ),
    'PopupMenuItem': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'DropdownButton': WidgetSpec(
      childSlots: {
        'hint': ChildSlotShape.single,
        'icon': ChildSlotShape.single,
      },
    ),
    'DropdownMenuItem': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'SnackBar': WidgetSpec(
      childSlots: {'content': ChildSlotShape.single},
    ),
    'ButtonBar': WidgetSpec(
      childSlots: {'children': ChildSlotShape.list},
    ),
    'OverflowBar': WidgetSpec(
      childSlots: {'children': ChildSlotShape.list},
    ),
    'Divider': WidgetSpec(),
    'VerticalDivider': WidgetSpec(),
    'Spacer': WidgetSpec(),
    'CircularProgressIndicator': WidgetSpec(),
    'LinearProgressIndicator': WidgetSpec(),
    'RefreshIndicator': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'Scrollbar': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
    'CupertinoScrollbar': WidgetSpec(
      childSlots: {'child': ChildSlotShape.single},
    ),
  };

  static WidgetSpec? specFor(String className) => _known[className];

  static bool isKnown(String className) => _known.containsKey(className);
}
