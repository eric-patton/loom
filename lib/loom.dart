/// Loom: AST<->visual-model bridge for Flutter widget source.
///
/// Pure-Dart kernel. The .dart source files are the source of truth; this
/// library exposes a structured model over their AST and emits minimal-diff
/// edits back. See PROJECT_SPEC.md for the contract and invariants.
library;

export 'src/catalog/route_catalog.dart' show RouteCatalog, RouteSpec;
export 'src/emission/edit_planner.dart';
export 'src/emission/property_serializer.dart';
export 'src/emission/route_edit_planner.dart';
export 'src/emission/route_serializer.dart';
export 'src/emission/source_edit.dart';
export 'src/emission/widget_serializer.dart';
export 'src/equivalence/model_equivalence.dart';
export 'src/model/list_slot_style.dart';
// node.dart hosts the full sealed hierarchy: ModelNode + WidgetNode +
// RouteNode + OpaqueNode + MethodReferenceNode + WidgetTreeModel +
// RouteTreeModel + ParseDiagnostic + kPositionalOpaqueKeyPrefix.
export 'src/model/node.dart';
export 'src/model/node_path.dart';
export 'src/model/property_value.dart';
export 'src/model/source_span.dart';
export 'src/model/style_hints.dart';
export 'src/parsing/route_tree_parser.dart';
export 'src/parsing/widget_tree_parser.dart';
export 'src/parsing/widget_visitor.dart' show ParseException;
