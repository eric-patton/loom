import 'list_slot_style.dart';
import 'property_value.dart';
import 'source_span.dart';
import 'style_hints.dart';
import 'widget_node.dart' show ParseDiagnostic;

/// Re-export so callers that only import `route_node.dart` can still see
/// the positional-opaque key prefix when building or inspecting routes.
export 'widget_node.dart' show ParseDiagnostic, kPositionalOpaqueKeyPrefix;

/// A node in a route-tree visual model (parallel to `ModelNode` for widgets).
///
/// Sealed: every node is one of `RouteNode` (a modeled route constructor call,
/// editable via the kernel API), `RouteOpaqueNode` (a verbatim source range
/// the kernel does not model — e.g. a `builder:` function literal), or
/// `RouteMethodReferenceNode` (an in-class helper-method reference resolved
/// to its returned route expression).
///
/// Why duplicate the opaque/method-ref variants instead of reusing the
/// widget side's `OpaqueNode` and `MethodReferenceNode`: Dart's sealed-class
/// semantics restrict cross-library `implements`, so a single type cannot
/// belong to two sealed hierarchies declared in different libraries.
/// M6.0 accepts this duplication; M6.1 will extract a shared base
/// (`loom_core`) once the seam between widget- and route-side machinery
/// is visible in real code rather than hypothetical.
sealed class RouteTreeNode {
  const RouteTreeNode();
  SourceSpan get sourceSpan;
}

/// A modeled route constructor call (`GoRouter(...)`, `GoRoute(...)`,
/// `ShellRoute(...)`, etc.). Same internal shape as `WidgetNode`: a name,
/// a property map, child slots grouped by name, and per-slot style hints.
class RouteNode extends RouteTreeNode {
  RouteNode({
    required this.className,
    required Map<String, PropertyValue> properties,
    required Map<String, List<RouteTreeNode>> childSlots,
    required this.sourceSpan,
    required this.styleHints,
    Map<String, ListSlotStyle> childSlotStyles =
        const <String, ListSlotStyle>{},
  })  : properties = Map.unmodifiable(properties),
        childSlots = Map.unmodifiable({
          for (final entry in childSlots.entries)
            entry.key: List<RouteTreeNode>.unmodifiable(entry.value),
        }),
        childSlotStyles = Map.unmodifiable(childSlotStyles);

  /// Class name of the constructor invoked — e.g. `'GoRouter'`, `'GoRoute'`.
  final String className;

  /// Modeled literal properties keyed by their named-argument label.
  /// Function-literal arguments like `builder: (ctx, state) => …` land in
  /// here as `OpaquePropertyValue` (the widget-side `OpaquePropertyValue`
  /// is reused — `PropertyValue` is already language-general).
  final Map<String, PropertyValue> properties;

  /// Route-valued named arguments grouped by their slot name. `routes:` is
  /// always list-shaped; future single-shaped slots (e.g. `redirect:` if it
  /// were modeled as a route reference) would follow `WidgetNode`'s pattern
  /// of a one-element list.
  final Map<String, List<RouteTreeNode>> childSlots;

  /// Per-list-slot style hints captured at parse time. Same role as on
  /// `WidgetNode`: preserves bracket span, trailing-comma state, and
  /// single-/multi-line shape across structural edits.
  final Map<String, ListSlotStyle> childSlotStyles;

  @override
  final SourceSpan sourceSpan;

  final StyleHints styleHints;

  @override
  String toString() {
    final totalChildren = childSlots.values.fold<int>(
      0,
      (sum, list) => sum + list.length,
    );
    return 'RouteNode($className @${sourceSpan.offset}+${sourceSpan.length}, '
        '${properties.length} prop(s), ${childSlots.length} slot(s), '
        '$totalChildren child(ren))';
  }
}

/// A region of a route-tree source the kernel does not model — typically
/// a `builder:` function literal or a non-list expression in a `routes:`
/// slot. Carries `sourceText` (verbatim bytes) in addition to `sourceSpan`,
/// matching the widget-side `OpaqueNode` rationale (post-reparse span
/// shifts; content is invariant).
class RouteOpaqueNode extends RouteTreeNode {
  const RouteOpaqueNode({required this.sourceSpan, required this.sourceText});

  @override
  final SourceSpan sourceSpan;

  final String sourceText;

  @override
  String toString() {
    final preview = sourceText.length > 30
        ? '${sourceText.substring(0, 30)}...'
        : sourceText;
    final escaped = preview.replaceAll('\n', '\\n');
    return 'RouteOpaqueNode(@${sourceSpan.offset}+${sourceSpan.length}, '
        '"$escaped")';
  }
}

/// A call to an in-class helper method that returns a route expression.
/// Parallel to `MethodReferenceNode` on the widget side. The `body` is the
/// resolved route tree at the helper's return expression; edits to `body`
/// translate to source edits at the helper's own location, not the call
/// site.
class RouteMethodReferenceNode extends RouteTreeNode {
  const RouteMethodReferenceNode({
    required this.methodName,
    required this.callSourceSpan,
    required this.body,
  });

  final String methodName;
  final SourceSpan callSourceSpan;
  final RouteTreeNode body;

  @override
  SourceSpan get sourceSpan => callSourceSpan;

  @override
  String toString() => 'RouteMethodReferenceNode($methodName -> $body)';
}

/// Public root of the route-tree visual model.
///
/// Same role as `WidgetTreeModel` on the widget side. `root` is typed as
/// the union `RouteTreeNode`, so an unmodelable root expression
/// (`GoRouter get router => _helper();`) lands as a
/// `RouteMethodReferenceNode` or `RouteOpaqueNode` rather than throwing.
/// `diagnostics` carries analyzer parse errors recovered from the source —
/// callers may surface them or refuse edits while the file is mid-edit.
class RouteTreeModel {
  const RouteTreeModel({
    required this.root,
    this.diagnostics = const <ParseDiagnostic>[],
  });

  final RouteTreeNode root;
  final List<ParseDiagnostic> diagnostics;

  @override
  String toString() => 'RouteTreeModel(rootType=${root.runtimeType}'
      '${diagnostics.isEmpty ? '' : ', ${diagnostics.length} diagnostic(s)'})';
}
