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

/// A json_serializable-style model class view.
///
/// Detection signal: class has a `@JsonSerializable(...)` annotation
/// (or the bare-pun shorthand `@JsonSerializable`).
///
/// Fields are real field declarations (not factory ctor params, as in
/// Freezed). Each field carries its optional `@JsonKey(...)` configuration.
///
/// The fromJson factory + toJson method aren't required for
/// recognition (some classes declare them; some rely entirely on the
/// generated mixin). When present, they're exposed via
/// `fromJsonConstructor` / `toJsonMethod`.
class JsonSerializableView {
  const JsonSerializableView._({
    required this.classNode,
    required this.annotation,
    required this.fields,
    required this.fromJsonConstructor,
    required this.toJsonMethod,
  });

  /// Returns a `JsonSerializableView` over [model] if the class is
  /// annotated `@JsonSerializable`, or null otherwise.
  static JsonSerializableView? from(ClassStructureModel model) {
    final cls = model.root;
    final ann = _findJsonSerializableAnnotation(cls.annotations);
    if (ann == null) return null;

    final fields = <JsonField>[];
    ClassConstructorNode? fromJson;
    ClassMethodNode? toJson;
    for (final member in cls.members) {
      if (member is ClassFieldNode) {
        if (member.isStatic) continue;
        fields.add(JsonField._(member));
      } else if (member is ClassConstructorNode &&
          member.isFactory &&
          member.namedConstructorName == 'fromJson') {
        fromJson = member;
      } else if (member is ClassMethodNode && member.name == 'toJson') {
        toJson = member;
      }
    }

    return JsonSerializableView._(
      classNode: cls,
      annotation: ann,
      fields: List.unmodifiable(fields),
      fromJsonConstructor: fromJson,
      toJsonMethod: toJson,
    );
  }

  final ClassStructureNode classNode;

  /// The `@JsonSerializable(...)` annotation that triggered
  /// recognition. Useful for editing global JSON config
  /// (`fieldRename: FieldRename.snake`, etc.).
  final AnnotationNode annotation;

  /// Instance fields of the class — what json_serializable serializes.
  /// Static fields are excluded.
  final List<JsonField> fields;

  /// The `factory Foo.fromJson(...)` constructor if present, or null.
  final ClassConstructorNode? fromJsonConstructor;

  /// The `Map<String, dynamic> toJson()` method if present, or null.
  final ClassMethodNode? toJsonMethod;

  @override
  String toString() => 'JsonSerializableView(${classNode.className}, '
      '${fields.length} field(s))';
}

/// A field within a json_serializable class — wraps a `ClassFieldNode`
/// plus its optional `@JsonKey(...)` configuration.
class JsonField {
  const JsonField._(this.field);

  /// The underlying field node. Use this for field-level edits.
  final ClassFieldNode field;

  String get name => field.name;
  SourceSpan get nameSpan => field.nameSpan;
  String? get typeName => field.typeName;
  List<AnnotationNode> get annotations => field.annotations;

  /// The `@JsonKey(...)` annotation on this field, if any. Captures
  /// per-field overrides like `name: 'first_name'` or
  /// `defaultValue: 0`.
  AnnotationNode? get jsonKey {
    for (final a in field.annotations) {
      if (a.name == 'JsonKey') return a;
    }
    return null;
  }

  /// The serialized JSON key for this field. Returns the `name:`
  /// argument of `@JsonKey` if specified, otherwise the field's
  /// Dart name (which is what json_serializable defaults to unless
  /// the class-level annotation has a `fieldRename:` setting —
  /// callers that need to apply that should consult `view.annotation`).
  String get jsonKeyName {
    final ann = jsonKey;
    if (ann == null) return name;
    for (final arg in ann.arguments) {
      if (arg is NamedAnnotationArgumentNode && arg.name == 'name') {
        // The value source is a string literal — strip quotes.
        return _stripQuotes(arg.valueSource) ?? name;
      }
    }
    return name;
  }

  @override
  String toString() => 'JsonField($name → $jsonKeyName)';
}

AnnotationNode? _findJsonSerializableAnnotation(
  List<AnnotationNode> annotations,
) {
  for (final a in annotations) {
    if (a.name == 'JsonSerializable') return a;
  }
  return null;
}

String? _stripQuotes(String source) {
  if (source.length < 2) return null;
  final first = source.codeUnitAt(0);
  final last = source.codeUnitAt(source.length - 1);
  if ((first == 0x27 /* ' */ || first == 0x22 /* " */) && first == last) {
    return source.substring(1, source.length - 1);
  }
  return null;
}

/// A Drift table class view.
///
/// Detection signal: class `extends Table` (the M10.1c `superclassName`
/// capture). Optionally check for `@DataClassName(...)` /
/// `@TableIndex(...)` annotations for richer metadata.
///
/// Columns are getters whose return type is one of the recognized
/// Drift column types: `IntColumn`, `TextColumn`, `BoolColumn`,
/// `RealColumn`, `BlobColumn`, `DateTimeColumn`. The implementation
/// body (e.g. `integer().autoIncrement()()`) is captured verbatim as
/// raw source — the kernel doesn't currently model the cascade.
///
/// Stretch: in a future milestone, parse the cascade to surface
/// individual modifiers (autoIncrement, named, withDefault, nullable)
/// as structured. For M10.1c the body is opaque.
class DriftTableView {
  const DriftTableView._({
    required this.classNode,
    required this.columns,
  });

  /// Returns a `DriftTableView` over [model] if it looks like a Drift
  /// table, or null otherwise.
  ///
  /// Recognition rule: class has `extends Table` (case-sensitive).
  /// This is a name-based match — won't catch tables that extend a
  /// custom intermediate base class. Callers with such projects
  /// should subclass or extend recognition manually.
  static DriftTableView? from(ClassStructureModel model) {
    final cls = model.root;
    if (cls.superclassName != 'Table') return null;

    final columns = <DriftColumn>[];
    for (final member in cls.members) {
      if (member is! ClassMethodNode) continue;
      if (!member.isGetter) continue;
      final returnType = member.returnType;
      if (returnType == null) continue;
      final columnType = _columnTypeOf(returnType);
      if (columnType == null) continue;
      columns.add(DriftColumn._(member: member, columnType: columnType));
    }

    return DriftTableView._(
      classNode: cls,
      columns: List.unmodifiable(columns),
    );
  }

  final ClassStructureNode classNode;

  /// The column getters of the table, in source order.
  final List<DriftColumn> columns;

  @override
  String toString() =>
      'DriftTableView(${classNode.className}, ${columns.length} column(s))';
}

/// One column in a Drift table — wraps a `ClassMethodNode` (the getter).
class DriftColumn {
  const DriftColumn._({required this.member, required this.columnType});

  /// The underlying getter member. Use this for edits.
  final ClassMethodNode member;

  /// The column type kind, derived from the return type.
  final DriftColumnType columnType;

  String get name => member.name;
  SourceSpan get nameSpan => member.nameSpan;
  SourceSpan? get bodySpan => member.bodySpan;

  @override
  String toString() => 'DriftColumn($name: ${columnType.name})';
}

/// The supported Drift column types — corresponds to the return type
/// of the column getter (`IntColumn`, `TextColumn`, etc.).
enum DriftColumnType {
  intColumn,
  textColumn,
  boolColumn,
  realColumn,
  blobColumn,
  dateTimeColumn,
}

DriftColumnType? _columnTypeOf(String returnType) {
  switch (returnType) {
    case 'IntColumn':
      return DriftColumnType.intColumn;
    case 'TextColumn':
      return DriftColumnType.textColumn;
    case 'BoolColumn':
      return DriftColumnType.boolColumn;
    case 'RealColumn':
      return DriftColumnType.realColumn;
    case 'BlobColumn':
      return DriftColumnType.blobColumn;
    case 'DateTimeColumn':
      return DriftColumnType.dateTimeColumn;
    default:
      return null;
  }
}
