import 'class_structure.dart';
import 'source_span.dart';

/// Recognized "data class" views over a `ClassStructureModel`.
///
/// M10.1 adds codegen-aware modeling — taking a parsed
/// `ClassStructureModel` and projecting it through a domain lens like
/// Freezed or json_serializable. The lens recognizes the class shape
/// purely structurally (annotation name + member shape) — no resolved
/// types, no package resolution. Most codegen patterns can be detected
/// by the annotation name alone with high precision; the trade-off is
/// false positives for projects that happen to define a same-named
/// annotation locally.
///
/// These views are NON-DESTRUCTIVE — they don't transform the model,
/// they expose a curated subset for the visual editor. Edits go
/// through the existing `ClassStructureEditPlanner` against the
/// underlying nodes the view exposes.
///
/// Returning null is the "this isn't a Freezed/Drift/etc. class"
/// signal. Callers can pattern-match across views to decide how to
/// present the class.

/// A Freezed-style data class view.
///
/// Detection signal: class has an `@freezed` (or `@unfreezed` /
/// `@Freezed(...)`) annotation. Variants come from factory
/// constructors with redirect bodies (`factory Foo(...) = _Foo;`).
///
/// Two shapes:
///   * **Singleton** — one factory constructor. Most Freezed classes.
///     `singletonFields` returns its field list.
///   * **Union** — multiple factory constructors (sealed union).
///     `variants` lists each constructor with its fields.
///
/// The optional `fromJson` constructor is recognized separately
/// (used by Freezed + json_serializable integration).
class FreezedView {
  const FreezedView._({
    required this.classNode,
    required this.variants,
    required this.fromJson,
  });

  /// Returns a `FreezedView` over [model] if it looks like a Freezed
  /// data class, or null otherwise.
  ///
  /// Recognition rules:
  ///   * Class has an annotation named `freezed`, `unfreezed`, or
  ///     `Freezed` (case-sensitive — these are the published names).
  ///   * Class has at least one factory constructor. (A `@freezed`
  ///     class with no factory ctors isn't useful in practice — but
  ///     we still recognize the shape so the visual editor can show
  ///     an empty class.)
  static FreezedView? from(ClassStructureModel model) {
    final cls = model.root;
    if (!_hasFreezedAnnotation(cls.annotations)) return null;

    final variants = <FreezedVariant>[];
    ClassConstructorNode? fromJsonCtor;
    for (final member in cls.members) {
      if (member is! ClassConstructorNode) continue;
      if (!member.isFactory) continue;
      if (member.namedConstructorName == 'fromJson') {
        fromJsonCtor = member;
        continue;
      }
      variants.add(FreezedVariant._(
        constructor: member,
        variantName: member.namedConstructorName,
      ));
    }

    return FreezedView._(
      classNode: cls,
      variants: List.unmodifiable(variants),
      fromJson: fromJsonCtor,
    );
  }

  /// The underlying class-structure node. Use this for class-level
  /// edits (rename, add annotation, etc.).
  final ClassStructureNode classNode;

  /// One entry per factory constructor (excluding `fromJson`).
  final List<FreezedVariant> variants;

  /// The `factory Foo.fromJson(...)` constructor if present, or null.
  final ClassConstructorNode? fromJson;

  /// Returns true if the class is a "singleton" — exactly one variant.
  /// Most Freezed classes hit this shape. `singletonFields` is the
  /// convenience accessor when this is true.
  bool get isSingleton => variants.length == 1;

  /// The field list for a singleton class. Returns null when the class
  /// is a union (more than one variant) — use `variants` to enumerate.
  List<FreezedField>? get singletonFields =>
      isSingleton ? variants.first.fields : null;

  @override
  String toString() => 'FreezedView(${classNode.className}, '
      '${variants.length} variant(s)'
      '${fromJson == null ? '' : ', fromJson'})';
}

/// One variant of a Freezed-style union — represents one factory
/// constructor.
class FreezedVariant {
  FreezedVariant._({
    required this.constructor,
    required this.variantName,
  });

  /// The underlying constructor node. Use this for ctor-level edits.
  final ClassConstructorNode constructor;

  /// The variant name — the named-constructor segment, or null for
  /// the default ctor (singleton shape).
  ///
  /// For `@freezed class Vehicle with _$Vehicle {
  ///   factory Vehicle.car(...) = _Car;
  ///   factory Vehicle.motorcycle(...) = _Motorcycle;
  /// }` the variant names are `car` and `motorcycle`.
  final String? variantName;

  /// Fields are the parameters of this factory constructor.
  List<FreezedField> get fields => [
        for (final p in constructor.parameters) FreezedField._(p),
      ];
}

/// A field within a Freezed variant — wraps a `ClassParameterNode`.
class FreezedField {
  const FreezedField._(this.parameter);

  /// The underlying parameter node. Use this for field-level edits via
  /// `ClassStructureEditPlanner` (rename, retype, change default,
  /// etc.).
  final ClassParameterNode parameter;

  String get name => parameter.name;
  SourceSpan get nameSpan => parameter.nameSpan;
  String? get typeName => parameter.typeName;
  bool get isRequired => parameter.isRequired;
  bool get isNamed => parameter.isNamed;
  String? get defaultValueSource => parameter.defaultValueSource;
  List<AnnotationNode> get annotations => parameter.annotations;
  SourceSpan get sourceSpan => parameter.sourceSpan;

  @override
  String toString() => 'FreezedField($name)';
}

bool _hasFreezedAnnotation(List<AnnotationNode> annotations) {
  for (final a in annotations) {
    if (a.name == 'freezed') return true;
    if (a.name == 'unfreezed') return true;
    if (a.name == 'Freezed') return true;
  }
  return false;
}
