import 'annotation.dart';
import 'node.dart' show ParseDiagnostic;
import 'source_span.dart';

export 'annotation.dart';
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
    List<AnnotationNode> annotations = const <AnnotationNode>[],
    this.superclassName,
    this.superclassSpan,
    List<String> mixinNames = const <String>[],
    List<SourceSpan> mixinSpans = const <SourceSpan>[],
    List<String> interfaceNames = const <String>[],
    List<SourceSpan> interfaceSpans = const <SourceSpan>[],
  })  : members = List.unmodifiable(members),
        annotations = List.unmodifiable(annotations),
        mixinNames = List.unmodifiable(mixinNames),
        mixinSpans = List.unmodifiable(mixinSpans),
        interfaceNames = List.unmodifiable(interfaceNames),
        interfaceSpans = List.unmodifiable(interfaceSpans);

  final String className;

  /// Superclass name from the `extends` clause, or null when the class
  /// has no `extends` clause (implicitly extends `Object`). Captured
  /// as raw source text — preserves generic args (`extends Foo<T>`)
  /// and prefixes (`extends prefix.Bar`).
  ///
  /// M10.1c capture. Pre-M10.1c models had no extends info.
  final String? superclassName;

  /// Span of the superclass name in source. Null when no `extends`.
  final SourceSpan? superclassSpan;

  /// Mixin names from the `with` clause, in source order. Each name
  /// is raw source text (may include generics or prefixes).
  ///
  /// M10.1c capture. Empty when the class has no `with` clause.
  final List<String> mixinNames;

  /// Source spans of each mixin name, aligned with `mixinNames`.
  final List<SourceSpan> mixinSpans;

  /// Interface names from the `implements` clause, in source order.
  /// Each name is raw source text.
  ///
  /// M10.1c capture. Empty when the class has no `implements` clause.
  final List<String> interfaceNames;

  /// Source spans of each interface name, aligned with `interfaceNames`.
  final List<SourceSpan> interfaceSpans;

  /// Span of the entire class declaration, from the `class` keyword to
  /// the closing `}` of the body.
  final SourceSpan classSpan;

  /// Span of the class body, from the opening `{` to the closing `}`
  /// (inclusive of both braces).
  final SourceSpan bodySpan;

  /// Class members in source order. Pattern-match on member type to
  /// distinguish fields, methods, constructors, and opaque entries.
  final List<ClassMember> members;

  /// Class-level annotations (`@freezed`, `@JsonSerializable()`, etc.)
  /// in source order. M7.2 captures them; edit operations on them are
  /// deferred to M7.3+.
  final List<AnnotationNode> annotations;

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

  /// Annotations attached to this member (`@override`, `@JsonKey(name: 'x')`,
  /// etc.), in source order. Empty when the member has no annotations.
  /// M7.2 captures annotations; M7.3+ may add edit operations on them.
  List<AnnotationNode> get annotations;
}

/// A modeled field declaration within a class.
///
/// Field initializers are captured as raw source text rather than as a
/// `PropertyValue`. M7.0 keeps the surface small; downstream consumers
/// can re-emit the initializer verbatim or replace it wholesale. Future
/// milestones may promote initializers to typed `PropertyValue`s for
/// cases where literal recognition is useful.
class ClassFieldNode extends ClassMember {
  ClassFieldNode({
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
    this.finalKeywordSpan,
    this.varKeywordSpan,
    this.lateKeywordSpan,
    this.staticKeywordSpan,
    List<AnnotationNode> annotations = const <AnnotationNode>[],
  }) : annotations = List.unmodifiable(annotations);

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

  /// Span of the `final` keyword token, when [isFinal] is true. Null
  /// otherwise. M7.5 captures these for qualifier-editing operations.
  final SourceSpan? finalKeywordSpan;

  /// Span of the `var` keyword token, when [isVar] is true. Null otherwise.
  final SourceSpan? varKeywordSpan;

  /// Span of the `late` keyword token, when [isLate] is true. Null otherwise.
  final SourceSpan? lateKeywordSpan;

  /// Span of the `static` keyword token, when [isStatic] is true. Null
  /// otherwise.
  final SourceSpan? staticKeywordSpan;

  @override
  final SourceSpan sourceSpan;

  @override
  final List<AnnotationNode> annotations;

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
  ClassMethodNode({
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
    this.staticKeywordSpan,
    List<ClassParameterNode> parameters = const <ClassParameterNode>[],
    List<AnnotationNode> annotations = const <AnnotationNode>[],
  })  : parameters = List.unmodifiable(parameters),
        annotations = List.unmodifiable(annotations);

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

  /// Span of the `static` keyword when [isStatic] is true. Null otherwise.
  /// M7.5 capture.
  final SourceSpan? staticKeywordSpan;

  @override
  final SourceSpan sourceSpan;

  /// Individual parameters (M7.2). Empty when [parametersSpan] is null
  /// (getters) or when the param list is `()`. The raw [parametersSource]
  /// is kept alongside for backward compat and for callers who want the
  /// verbatim text including parens / brackets.
  final List<ClassParameterNode> parameters;

  @override
  final List<AnnotationNode> annotations;

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
  ClassConstructorNode({
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
    this.constKeywordSpan,
    this.factoryKeywordSpan,
    List<ClassParameterNode> parameters = const <ClassParameterNode>[],
    List<AnnotationNode> annotations = const <AnnotationNode>[],
  })  : parameters = List.unmodifiable(parameters),
        annotations = List.unmodifiable(annotations);

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

  /// Span of the `const` keyword when [isConst] is true. Null otherwise.
  /// M7.5 capture.
  final SourceSpan? constKeywordSpan;

  /// Span of the `factory` keyword when [isFactory] is true. Null
  /// otherwise. M7.5 capture.
  final SourceSpan? factoryKeywordSpan;

  @override
  final SourceSpan sourceSpan;

  /// Individual parameters (M7.2). Same role as on `ClassMethodNode`.
  final List<ClassParameterNode> parameters;

  @override
  final List<AnnotationNode> annotations;

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

  /// Opaque members can't have modeled annotations — by definition the
  /// kernel didn't decode the member at all.
  @override
  List<AnnotationNode> get annotations => const <AnnotationNode>[];

  @override
  String toString() =>
      'OpaqueClassMember(@${sourceSpan.offset}+${sourceSpan.length})';
}

/// A modeled parameter within a method or constructor parameter list.
///
/// M7.2 captures full parameter shape — name, type, default value, and
/// kind flags — replacing the M7.1 `parametersSource: String` blob that
/// only allowed wholesale param-list replacement. Now individual
/// parameters can be added, removed, renamed, retyped, or have their
/// default values changed.
///
/// Function-typed parameters (`void Function() callback`) and
/// generic-function-typed parameters round-trip via the raw
/// [sourceSpan] but their internal structure isn't modeled — too rare
/// in real-world entity/data classes to justify the surface in M7.2.
class ClassParameterNode {
  ClassParameterNode({
    required this.name,
    required this.nameSpan,
    required this.typeName,
    required this.typeSpan,
    required this.defaultValueSource,
    required this.defaultValueSpan,
    required this.isRequired,
    required this.isNamed,
    required this.isPositional,
    required this.isOptional,
    required this.isThis,
    required this.isSuper,
    required this.isFinal,
    required this.isConst,
    required this.sourceSpan,
    this.requiredKeywordSpan,
    this.finalKeywordSpan,
    this.constKeywordSpan,
    List<AnnotationNode> annotations = const <AnnotationNode>[],
  }) : annotations = List.unmodifiable(annotations);

  /// Parameter name. May be empty for unnamed parameters (e.g. inside
  /// generic function-type aliases) — those don't appear in well-formed
  /// class members so the model assumes non-empty in practice.
  final String name;
  final SourceSpan nameSpan;

  /// Declared type as raw source text, or null if the parameter is
  /// untyped (`{required this.foo}` style, where the type comes from
  /// the field). For function-typed params this is the return type of
  /// the function (rare in entity classes).
  final String? typeName;
  final SourceSpan? typeSpan;

  /// Default value as raw source text (`'foo'`, `42`, `const []`), or
  /// null when the parameter has no default. Excludes the `=` separator;
  /// span starts at the value expression.
  final String? defaultValueSource;
  final SourceSpan? defaultValueSpan;

  /// Required: prefixed with `required` keyword (or positional, which is
  /// implicitly required). NOTE: a named parameter annotated with the
  /// older `@required` does NOT set this; modern code uses the keyword.
  final bool isRequired;

  /// Named: appears inside `{ ... }` braces. May be required or optional.
  final bool isNamed;

  /// Positional: appears outside `{ ... }`. May be required or optional.
  final bool isPositional;

  /// Optional: appears inside `[ ... ]` (positional optional) or `{ ... }`
  /// (named optional). Mutually exclusive with required for positional;
  /// named params are optional unless `required` is present.
  final bool isOptional;

  /// `this.x` form — initializing formal that's tied to a class field.
  final bool isThis;

  /// `super.x` form — forwarding parameter to a superclass constructor.
  final bool isSuper;

  final bool isFinal;
  final bool isConst;

  /// Span of the `required` keyword when [isRequired] && [isNamed]. Null
  /// otherwise. M7.5 capture. (Positional params are implicitly required
  /// — no keyword to capture.)
  final SourceSpan? requiredKeywordSpan;

  /// Span of the `final` keyword when [isFinal]. Null otherwise.
  /// M7.5 capture.
  final SourceSpan? finalKeywordSpan;

  /// Span of the `const` keyword when [isConst]. Null otherwise.
  /// M7.5 capture.
  final SourceSpan? constKeywordSpan;

  /// Span of the full parameter declaration including type, name, and
  /// any default value, but excluding inter-parameter separators (`,`)
  /// and surrounding delimiters (`(`, `[`, `{`).
  final SourceSpan sourceSpan;

  final List<AnnotationNode> annotations;

  @override
  String toString() {
    final mods = <String>[
      if (isRequired && isNamed) 'required',
      if (isFinal) 'final',
      if (isConst) 'const',
    ];
    final prefix = isThis ? 'this.' : (isSuper ? 'super.' : '');
    final type = typeName ?? '';
    final def = defaultValueSource == null ? '' : ' = $defaultValueSource';
    return 'ClassParameterNode(${mods.join(' ')}'
        '${mods.isNotEmpty ? ' ' : ''}'
        '$type${type.isNotEmpty ? ' ' : ''}'
        '$prefix$name$def)';
  }
}

// AnnotationNode (and AnnotationArgumentNode subtypes) live in
// `annotation.dart` and are re-exported from this file so that the
// class-structure surface continues to expose them as before.
