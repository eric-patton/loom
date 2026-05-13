/// Loom: AST<->visual-model bridge for Flutter widget source.
///
/// Pure-Dart kernel. The .dart source files are the source of truth; this
/// library exposes a structured model over their AST and emits minimal-diff
/// edits back. See PROJECT_SPEC.md for the contract and invariants.
library;

export 'src/emission/edit_planner.dart';
export 'src/emission/property_serializer.dart';
export 'src/emission/source_edit.dart';
export 'src/equivalence/model_equivalence.dart';
export 'src/model/node_path.dart';
export 'src/model/property_value.dart';
export 'src/model/source_span.dart';
export 'src/model/style_hints.dart';
export 'src/model/widget_node.dart';
export 'src/parsing/widget_tree_parser.dart';
export 'src/parsing/widget_visitor.dart' show ParseException;
