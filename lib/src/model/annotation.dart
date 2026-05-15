import 'source_span.dart';

/// A modeled annotation attached to any declaration — class, member,
/// parameter, top-level function/variable/typedef, etc.
///
/// Captures the structural shape: name, optional arguments source,
/// and source spans for editing.
///
/// Argument internals (positional vs. named, individual values) are
/// captured by [arguments] (M10.0b). Pre-M10.0b code can still
/// inspect [argumentsSource] for the raw text.
class AnnotationNode {
  AnnotationNode({
    required this.name,
    required this.nameSpan,
    required this.argumentsSource,
    required this.argumentsSpan,
    required this.sourceSpan,
    List<AnnotationArgumentNode> arguments = const <AnnotationArgumentNode>[],
  }) : arguments = List.unmodifiable(arguments);

  /// The annotation name as a single identifier (`'override'`,
  /// `'JsonKey'`, `'freezed'`). For prefixed annotations
  /// (`@meta.required`), this captures the full dotted source text.
  final String name;
  final SourceSpan nameSpan;

  /// Argument-list source text including parens (`'()'`,
  /// `"(name: 'x')"`), or null when the annotation has no parens
  /// (bare `@override`).
  final String? argumentsSource;
  final SourceSpan? argumentsSpan;

  /// Span of the full annotation including the leading `@`.
  final SourceSpan sourceSpan;

  /// Modeled arguments inside the parentheses, in source order. Empty
  /// when [argumentsSource] is null OR when the parentheses are empty
  /// (`@JsonSerializable()`). Mix of positional and named.
  ///
  /// M10.0b capture. Pre-M10.0b annotations had `arguments = const []`
  /// effectively; callers that only need the raw text should keep using
  /// [argumentsSource].
  final List<AnnotationArgumentNode> arguments;

  @override
  String toString() => 'AnnotationNode(@$name${argumentsSource ?? ''})';
}

/// An individual argument inside an annotation's parentheses.
///
/// Sealed across positional + named. Each carries:
///   * The value source text (raw — could be a literal, a constant
///     identifier, a constructor call, etc. — the kernel doesn't
///     interpret).
///   * Source spans for editing.
///
/// Positional vs. named is determined by which subtype matches.
sealed class AnnotationArgumentNode {
  const AnnotationArgumentNode();

  /// Span of the full argument including the `name: ` prefix when
  /// named. Excludes the inter-argument `,` separator.
  SourceSpan get sourceSpan;

  /// Raw source of the argument's value (right-hand side of `:` for
  /// named, the whole arg for positional). The kernel doesn't model
  /// the value's structure — it's a verbatim source slice.
  String get valueSource;

  /// Span of the value portion. For named arguments, this is the
  /// right-hand side; for positional arguments, the whole expression.
  SourceSpan get valueSpan;
}

/// A positional argument: `@Foo('bar', 42)` — each unnamed value.
class PositionalAnnotationArgumentNode extends AnnotationArgumentNode {
  const PositionalAnnotationArgumentNode({
    required this.valueSource,
    required this.valueSpan,
    required this.sourceSpan,
  });

  @override
  final String valueSource;
  @override
  final SourceSpan valueSpan;
  @override
  final SourceSpan sourceSpan;

  @override
  String toString() => 'PositionalAnnotationArgumentNode($valueSource)';
}

/// A named argument: `@JsonKey(name: 'foo', defaultValue: 0)` — each
/// `name: value` pair.
class NamedAnnotationArgumentNode extends AnnotationArgumentNode {
  const NamedAnnotationArgumentNode({
    required this.name,
    required this.nameSpan,
    required this.valueSource,
    required this.valueSpan,
    required this.sourceSpan,
  });

  /// The argument name (e.g. `'name'` in `name: 'foo'`).
  final String name;

  /// Span of just the name identifier.
  final SourceSpan nameSpan;

  @override
  final String valueSource;
  @override
  final SourceSpan valueSpan;
  @override
  final SourceSpan sourceSpan;

  @override
  String toString() => 'NamedAnnotationArgumentNode($name: $valueSource)';
}
