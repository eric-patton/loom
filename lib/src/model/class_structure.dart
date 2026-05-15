import 'node.dart' show ParseDiagnostic;
import 'source_span.dart';

export 'node.dart' show ParseDiagnostic;

/// A modeled Dart class declaration. M7.0 first slice: surfaces field
/// declarations as editable nodes; method, constructor, and getter/setter
/// declarations are preserved as opaque source-span entries.
///
/// **Deliberately not a `ModelNode` variant.** The constructor-tree
/// `ModelNode` hierarchy (`WidgetNode` / `RouteNode` / `PipelineNode` /
/// `OpaqueNode` / `MethodReferenceNode`) models *trees of expressions* —
/// every node has named child slots and a constructor-call shape. A class
/// is a *flat list of members* with member-specific shape. Forcing class
/// structure into `ModelNode` would either dilute the constructor-call
/// semantics or require contorting the model. M7+ may eventually
/// introduce a shared `LoomModel` umbrella; for now, separate hierarchies
/// are the honest representation.
class ClassStructureModel {
  const ClassStructureModel({
    required this.root,
    this.diagnostics = const <ParseDiagnostic>[],
  });

  final ClassStructureNode root;
  final List<ParseDiagnostic> diagnostics;

  @override
  String toString() => 'ClassStructureModel(class=${root.className}, '
      '${root.fields.length} field(s), '
      '${root.opaqueMemberSpans.length} opaque member(s)'
      '${diagnostics.isEmpty ? '' : ', ${diagnostics.length} diagnostic(s)'})';
}

/// Root of a class-structure model. Captures the class name plus enough
/// span information that edits can target the body's interior (for
/// `addField`) without touching the class header or surrounding code.
///
/// `opaqueMemberSpans` preserves the source ranges of non-field members
/// (methods, constructors, getters/setters, factory declarations).
/// Structural edits avoid these ranges; M7.0 doesn't model them.
class ClassStructureNode {
  ClassStructureNode({
    required this.className,
    required this.classSpan,
    required this.bodySpan,
    required List<ClassFieldNode> fields,
    required List<SourceSpan> opaqueMemberSpans,
  })  : fields = List.unmodifiable(fields),
        opaqueMemberSpans = List.unmodifiable(opaqueMemberSpans);

  final String className;

  /// Span of the entire class declaration, from the `class` keyword to
  /// the closing `}` of the body.
  final SourceSpan classSpan;

  /// Span of the class body, from the opening `{` to the closing `}`
  /// (inclusive of both braces).
  final SourceSpan bodySpan;

  /// Field declarations in source order. Each entry is a single
  /// declaration even when one source `FieldDeclaration` declares
  /// multiple variables (`final String a, b;` becomes two
  /// `ClassFieldNode`s, both pointing at the shared declaration span).
  final List<ClassFieldNode> fields;

  /// Source spans of the non-field members the model didn't capture —
  /// methods, constructors, getters/setters. M7.0 treats them as opaque
  /// regions: their bytes are preserved verbatim through any edit to the
  /// class structure that doesn't directly target them.
  final List<SourceSpan> opaqueMemberSpans;

  @override
  String toString() => 'ClassStructureNode($className, '
      '${fields.length} field(s), ${opaqueMemberSpans.length} opaque)';
}

/// A modeled field declaration within a class.
///
/// Field initializers are captured as raw source text (`initializerSource`)
/// rather than as a `PropertyValue`. M7.0 keeps the surface small;
/// downstream consumers can re-emit the initializer verbatim or replace it
/// wholesale. Future milestones may promote initializers to typed
/// `PropertyValue`s for cases where literal recognition is useful.
class ClassFieldNode {
  const ClassFieldNode({
    required this.name,
    required this.nameSpan,
    required this.typeName,
    required this.typeSpan,
    required this.initializerSource,
    required this.initializerSpan,
    required this.isFinal,
    required this.isVar,
    required this.isLate,
    required this.isStatic,
    required this.sourceSpan,
  });

  /// Field name (`name` in `final String name = 'x';`).
  final String name;

  /// Span of just the name token within the source.
  final SourceSpan nameSpan;

  /// Declared type as it appears in source (`String`, `Map<String, int>`,
  /// `List<T>?`), or null if untyped (`var foo;`). Captured as raw source
  /// text so generics and nullability markers round-trip verbatim without
  /// the model having to understand them.
  final String? typeName;

  /// Span of the type annotation in source. Null when `typeName` is null.
  final SourceSpan? typeSpan;

  /// Initializer expression as raw source text (`'x'`, `42`, `[1, 2]`,
  /// `SomeCall()`), or null if the field has no initializer.
  final String? initializerSource;

  /// Span of just the initializer expression (excluding the `=` and any
  /// trailing whitespace before `;`). Null when no initializer.
  final SourceSpan? initializerSpan;

  final bool isFinal;
  final bool isVar;
  final bool isLate;
  final bool isStatic;

  /// Span of the full field declaration, from the first qualifier (or
  /// type) to the trailing `;`. Used by removeField to delete the whole
  /// declaration and its terminator together.
  final SourceSpan sourceSpan;

  @override
  String toString() {
    final qualifiers = <String>[
      if (isStatic) 'static',
      if (isLate) 'late',
      if (isFinal) 'final',
      if (isVar) 'var',
    ];
    final type = typeName ?? '';
    return 'ClassFieldNode(${qualifiers.join(' ')}'
        '${qualifiers.isNotEmpty ? ' ' : ''}'
        '$type${type.isNotEmpty ? ' ' : ''}'
        '$name${initializerSource == null ? '' : ' = $initializerSource'})';
  }
}
