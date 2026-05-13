/// Metadata for the (small) set of widgets M1 actually models.
///
/// The parser consults the catalog for two questions:
///   1. Which named argument feeds this widget's children, and is the slot
///      single-shaped (`child:`) or list-shaped (`children:`)?
///   2. Which positional arguments map to which model properties (e.g.
///      `Text('hello')` -> property `data`)?
///
/// Widgets not in the catalog will cause the parser to throw in M1. The
/// corpus-expansion follow-up plan will decide on proto-opaque handling.
class WidgetSpec {
  const WidgetSpec({
    this.childrenParam,
    this.isChildrenList = false,
    this.positionalToProperty = const <int, String>{},
  });

  /// The named parameter that holds child widgets — e.g. `'children'` on
  /// `Column`, `'child'` on `Padding`. Null when this widget has no child
  /// slot (e.g. `Text`).
  final String? childrenParam;

  /// `true` if `childrenParam` is list-shaped (`children: [w, w]`); `false`
  /// if single-shaped (`child: w`). Ignored when `childrenParam` is null.
  final bool isChildrenList;

  /// Maps positional argument index to model property name.
  final Map<int, String> positionalToProperty;
}

class WidgetCatalog {
  WidgetCatalog._();

  static const Map<String, WidgetSpec> _known = <String, WidgetSpec>{
    'Column': WidgetSpec(childrenParam: 'children', isChildrenList: true),
    'Padding': WidgetSpec(childrenParam: 'child'),
    'Text': WidgetSpec(positionalToProperty: <int, String>{0: 'data'}),
  };

  static WidgetSpec? specFor(String className) => _known[className];

  static bool isKnown(String className) => _known.containsKey(className);
}
