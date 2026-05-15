import 'node.dart' show ParseDiagnostic;
import 'source_span.dart';

export 'node.dart' show ParseDiagnostic;

/// A modeled Dart class declaration.
///
/// M7.0 first slice modeled only fields. M7.1 extended the model to cover
/// methods (including getters/setters) and constructors. The members list
/// is sealed across `ClassFieldNode | ClassMethodNode |
/// ClassConstructorNode | OpaqueClassMember`, preserving source order.
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
      '${root.members.length} member(s)'
      '${diagnostics.isEmpty ? '' : ', ${diagnostics.length} diagnostic(s)'})';
}

/// Root of a class-structure model. Captures the class name plus the
/// members list. Span info anchors edits against the body's interior
/// without touching the class header or surrounding code.
class ClassStructureNode {
  ClassStructureNode({
    required this.className,
    required this.classSpan,
    required this.bodySpan,
    required List<ClassMember> members,
  }) : members = List.unmodifiable(members);

  final String className;

  /// Span of the entire class declaration, from the `class` keyword to
  /// the closing `}` of the body.
  final SourceSpan classSpan;

  /// Span of the class body, from the opening `{` to the closing `}`
  /// (inclusive of both braces).
  final SourceSpan bodySpan;

  /// Class members in source order. Pattern-match on member type to
  /// distinguish fields, methods, constructors, and opaque entries.
  final List<ClassMember> members;

  /// Backward-compat view of just the field members. Pre-M7.1 callers
  /// that iterated `node.fields` keep working.
  List<ClassFieldNode> get fields =>
      members.whereType<ClassFieldNode>().toList(growable: false);

  /// Backward-compat view of opaque-member spans. Pre-M7.1 callers that
  /// iterated `node.opaqueMemberSpans` keep working.
  List<SourceSpan> get opaqueMemberSpans => members
      .whereType<OpaqueClassMember>()
      .map((m) => m.sourceSpan)
      .toList(growable: false);

  @override
  String toString() => 'ClassStructureNode($className, '
      '${members.length} member(s))';
}

/// Base type for a class member.
///
/// Sealed across the four concrete kinds the parser produces:
///   * `ClassFieldNode` — `final String name;` and similar
///   * `ClassMethodNode` — instance/static methods, getters, setters
///   * `ClassConstructorNode` — default or named constructors, including
///     factories and redirecting ctors
///   * `OpaqueClassMember` — anything else the parser doesn't model
///     (rare; should be empty in well-formed Dart)
sealed class ClassMember {
  const ClassMember();

  /// Span of the full member declaration, from the first qualifier (or
  /// type / annotation) to the trailing `;` or `}`.
  SourceSpan get sourceSpan;
}

/// A modeled field declaration within a class.
///
/// Field initializers are captured as raw source text rather than as a
/// `PropertyValue`. M7.0 keeps the surface small; downstream consumers
/// can re-emit the initializer verbatim or replace it wholesale. Future
/// milestones may promote initializers to typed `PropertyValue`s for
/// cases where literal recognition is useful.
class ClassFieldNode extends ClassMember {
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

  /// Initializer expression as raw source text, or null if the field has
  /// no initializer.
  final String? initializerSource;

  /// Span of just the initializer expression. Null when no initializer.
  final SourceSpan? initializerSpan;

  final bool isFinal;
  final bool isVar;
  final bool isLate;
  final bool isStatic;

  @override
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

/// A modeled method declaration — instance methods, static methods,
/// getters, and setters.
///
/// M7.1 captures the signature (name, return type, parameters as raw
/// source text) plus a span for the body. Parameter structure is NOT
/// modeled — parameters are a raw source-text string with a span, so
/// they can be replaced wholesale but not individually edited. That's
/// M7.2 territory.
class ClassMethodNode extends ClassMember {
  const ClassMethodNode({
    required this.name,
    required this.nameSpan,
    required this.returnType,
    required this.returnTypeSpan,
    required this.parametersSource,
    required this.parametersSpan,
    required this.bodySpan,
    required this.isStatic,
    required this.isAbstract,
    required this.isGetter,
    required this.isSetter,
    required this.isOperator,
    required this.isAsync,
    required this.isGenerator,
    required this.sourceSpan,
  });

  /// Method name (e.g. `'isAdult'`, `'fullName'` for a getter,
  /// `'+'` for an operator).
  final String name;
  final SourceSpan nameSpan;

  /// Return type as raw source text (`'bool'`, `'String'`, `'List<T>?'`),
  /// or null when the source omits a return type.
  final String? returnType;
  final SourceSpan? returnTypeSpan;

  /// Parameter list as raw source text including the surrounding `(` and
  /// `)`, or null for getters (which have no parameter list).
  final String? parametersSource;
  final SourceSpan? parametersSpan;

  /// Body span — covers `=> expr;`, `{ ... }`, or `;` for abstract
  /// declarations. Null is unexpected (every method has SOME body
  /// representation).
  final SourceSpan? bodySpan;

  final bool isStatic;
  final bool isAbstract;
  final bool isGetter;
  final bool isSetter;
  final bool isOperator;
  final bool isAsync;

  /// True for `sync*` / `async*` generator methods.
  final bool isGenerator;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() {
    final qualifiers = <String>[
      if (isStatic) 'static',
      if (isAbstract) 'abstract',
      if (isGetter) 'get',
      if (isSetter) 'set',
      if (isOperator) 'operator',
    ];
    final ret = returnType ?? '';
    final params = parametersSource ?? '';
    final modifiers = <String>[
      if (isAsync) 'async',
      if (isGenerator) '*',
    ];
    return 'ClassMethodNode(${qualifiers.join(' ')}'
        '${qualifiers.isNotEmpty ? ' ' : ''}'
        '$ret${ret.isNotEmpty ? ' ' : ''}'
        '$name$params${modifiers.join('')})';
  }
}

/// A modeled constructor declaration — default, named, or factory.
///
/// M7.1 captures the structural shape: optional named-constructor name,
/// parameters as raw source text, initializer-list as raw source text,
/// and body span. Parameter and initializer structure are NOT modeled —
/// they round-trip verbatim. That's M7.2+ territory.
class ClassConstructorNode extends ClassMember {
  const ClassConstructorNode({
    required this.className,
    required this.classNameSpan,
    required this.namedConstructorName,
    required this.namedConstructorSpan,
    required this.parametersSource,
    required this.parametersSpan,
    required this.initializerListSource,
    required this.initializerListSpan,
    required this.bodySpan,
    required this.isConst,
    required this.isFactory,
    required this.sourceSpan,
  });

  /// The class name as it appears in the constructor declaration.
  /// Always present — Dart constructors always lead with the class name.
  final String className;
  final SourceSpan classNameSpan;

  /// Named-constructor segment (e.g. `'fromJson'` in `User.fromJson(...)`),
  /// or null for the default constructor.
  final String? namedConstructorName;
  final SourceSpan? namedConstructorSpan;

  /// Parameter list as raw source text including the surrounding `(`
  /// and `)`. Always present.
  final String parametersSource;
  final SourceSpan parametersSpan;

  /// Initializer-list source text (`: super(...), this.x = y`), or null
  /// when the constructor has none. Span starts at the `:` and runs
  /// through the last initializer.
  final String? initializerListSource;
  final SourceSpan? initializerListSpan;

  /// Body span — covers `{ ... }`, `;`, or a redirecting `= OtherCtor;`.
  /// Always present.
  final SourceSpan bodySpan;

  final bool isConst;
  final bool isFactory;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() {
    final qualifiers = <String>[
      if (isFactory) 'factory',
      if (isConst) 'const',
    ];
    final name = namedConstructorName == null
        ? className
        : '$className.$namedConstructorName';
    return 'ClassConstructorNode(${qualifiers.join(' ')}'
        '${qualifiers.isNotEmpty ? ' ' : ''}'
        '$name$parametersSource)';
  }
}

/// A class member the parser didn't model.
///
/// In practice, M7.1 covers field, method (including getter/setter), and
/// constructor declarations — virtually all real-world class members.
/// This variant exists for forward-compat (analyzer may introduce new
/// `ClassMember` subtypes the parser doesn't yet recognize) and to keep
/// the model total: every source member maps to a `ClassMember`,
/// preserving source order.
class OpaqueClassMember extends ClassMember {
  const OpaqueClassMember({required this.sourceSpan});

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() =>
      'OpaqueClassMember(@${sourceSpan.offset}+${sourceSpan.length})';
}
