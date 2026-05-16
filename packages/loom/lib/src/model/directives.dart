import 'node.dart' show ParseDiagnostic;
import 'source_span.dart';

export 'node.dart' show ParseDiagnostic;

/// A modeled view of a Dart compilation unit's top-level directives —
/// `library`, `import`, `export`, `part`, `part of`.
///
/// This is the first cross-file modeling surface (M9). Unlike the
/// per-file widget/route/class/function-body models, directives are
/// inherently about a file's relationship to other files (the imported
/// URIs, the exported re-exports, the parts that make up a multi-part
/// library). Together with `M9.0b`'s `ProjectModel`, they form the
/// kernel's project-level view.
///
/// `CompilationUnitDirectives` is the root model. It holds an ordered
/// list of directives plus a "directive section end" offset that's
/// useful for inserting new imports without scanning manually.
class CompilationUnitDirectives {
  CompilationUnitDirectives({
    required List<DirectiveNode> directives,
    required this.directiveSectionEnd,
    this.diagnostics = const <ParseDiagnostic>[],
  }) : directives = List.unmodifiable(directives);

  /// Directives in source order.
  final List<DirectiveNode> directives;

  /// Offset just after the last directive's trailing newline (or
  /// just after the file's BOM/library comment block when there are
  /// no directives). Use this as the insertion point for new imports
  /// when the existing directives don't make a natural anchor.
  final int directiveSectionEnd;

  final List<ParseDiagnostic> diagnostics;

  /// Just the import directives in source order. Convenience.
  Iterable<ImportDirectiveNode> get imports =>
      directives.whereType<ImportDirectiveNode>();

  /// Just the export directives.
  Iterable<ExportDirectiveNode> get exports =>
      directives.whereType<ExportDirectiveNode>();

  /// Just the part directives.
  Iterable<PartDirectiveNode> get parts =>
      directives.whereType<PartDirectiveNode>();

  @override
  String toString() =>
      'CompilationUnitDirectives(${directives.length} directive(s))';
}

/// Base type for a top-level directive. Sealed across the five Dart
/// directive forms: `library`, `import`, `export`, `part`, `part of`.
sealed class DirectiveNode {
  const DirectiveNode();

  /// Span of the full directive including its trailing `;`.
  SourceSpan get sourceSpan;
}

/// A `library [name];` directive. `name` is optional in Dart 2.12+;
/// when present, it's a dot-separated identifier (`my.lib.name`).
class LibraryDirectiveNode extends DirectiveNode {
  const LibraryDirectiveNode({
    required this.libraryKeywordSpan,
    required this.name,
    required this.nameSpan,
    required this.sourceSpan,
  });

  final SourceSpan libraryKeywordSpan;

  /// The library's name (e.g. `'my.lib.name'`), or null for unnamed
  /// library directives (`library;`).
  final String? name;
  final SourceSpan? nameSpan;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() => 'LibraryDirectiveNode(${name ?? '(unnamed)'})';
}

/// An `import 'uri' [as prefix] [combinator]* [deferred];` directive.
class ImportDirectiveNode extends DirectiveNode {
  ImportDirectiveNode({
    required this.importKeywordSpan,
    required this.uri,
    required this.uriSpan,
    required this.deferredKeywordSpan,
    required this.asKeywordSpan,
    required this.prefix,
    required this.prefixSpan,
    required List<CombinatorNode> combinators,
    required this.sourceSpan,
  }) : combinators = List.unmodifiable(combinators);

  final SourceSpan importKeywordSpan;

  /// The imported URI WITHOUT surrounding quotes (e.g.
  /// `'package:foo/bar.dart'` → `'package:foo/bar.dart'`).
  final String uri;

  /// Span of the URI literal INCLUDING quotes.
  final SourceSpan uriSpan;

  /// Span of the optional `deferred` keyword.
  final SourceSpan? deferredKeywordSpan;

  /// Span of the optional `as` keyword.
  final SourceSpan? asKeywordSpan;

  /// The optional prefix name (e.g. `b` in `import '...' as b`).
  final String? prefix;
  final SourceSpan? prefixSpan;

  /// Show / hide combinators in source order. An import may have
  /// multiple of each: `import 'utils.dart' show foo show bar hide baz;`.
  final List<CombinatorNode> combinators;

  @override
  final SourceSpan sourceSpan;

  /// True when this is a deferred import (`deferred as ...`).
  bool get isDeferred => deferredKeywordSpan != null;

  @override
  String toString() =>
      'ImportDirectiveNode(\'$uri\'${prefix == null ? '' : ' as $prefix'})';
}

/// An `export 'uri' [combinator]*;` directive. Like `ImportDirectiveNode`
/// but without prefix / deferred support.
class ExportDirectiveNode extends DirectiveNode {
  ExportDirectiveNode({
    required this.exportKeywordSpan,
    required this.uri,
    required this.uriSpan,
    required List<CombinatorNode> combinators,
    required this.sourceSpan,
  }) : combinators = List.unmodifiable(combinators);

  final SourceSpan exportKeywordSpan;
  final String uri;
  final SourceSpan uriSpan;
  final List<CombinatorNode> combinators;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() => 'ExportDirectiveNode(\'$uri\')';
}

/// A `part 'uri';` directive — declares that the named file is part
/// of this library.
class PartDirectiveNode extends DirectiveNode {
  const PartDirectiveNode({
    required this.partKeywordSpan,
    required this.uri,
    required this.uriSpan,
    required this.sourceSpan,
  });

  final SourceSpan partKeywordSpan;
  final String uri;
  final SourceSpan uriSpan;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() => 'PartDirectiveNode(\'$uri\')';
}

/// A `part of 'main.dart';` or `part of mylib;` directive — declares
/// that THIS file is a part of the named library.
class PartOfDirectiveNode extends DirectiveNode {
  const PartOfDirectiveNode({
    required this.partKeywordSpan,
    required this.ofKeywordSpan,
    required this.libraryName,
    required this.libraryNameSpan,
    required this.uri,
    required this.uriSpan,
    required this.sourceSpan,
  });

  final SourceSpan partKeywordSpan;
  final SourceSpan ofKeywordSpan;

  /// Dotted-name form: `part of my.lib.name;`. Mutually exclusive
  /// with [uri].
  final String? libraryName;
  final SourceSpan? libraryNameSpan;

  /// URI form: `part of 'main.dart';`. Mutually exclusive with
  /// [libraryName]. Preferred in Dart 2.19+.
  final String? uri;
  final SourceSpan? uriSpan;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() => uri != null
      ? 'PartOfDirectiveNode(\'$uri\')'
      : 'PartOfDirectiveNode($libraryName)';
}

/// Base type for a combinator on an import/export — `show foo, bar` or
/// `hide baz, qux`. Sealed across the two combinator kinds.
sealed class CombinatorNode {
  const CombinatorNode();
  SourceSpan get sourceSpan;
  SourceSpan get keywordSpan;
  List<String> get names;
  List<SourceSpan> get nameSpans;
}

/// A `show name1, name2, ...` combinator.
class ShowCombinatorNode extends CombinatorNode {
  ShowCombinatorNode({
    required this.keywordSpan,
    required List<String> names,
    required List<SourceSpan> nameSpans,
    required this.sourceSpan,
  })  : names = List.unmodifiable(names),
        nameSpans = List.unmodifiable(nameSpans),
        assert(
          names.length == nameSpans.length,
          'names and nameSpans must have the same length',
        );

  @override
  final SourceSpan keywordSpan;

  @override
  final List<String> names;

  @override
  final List<SourceSpan> nameSpans;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() => 'ShowCombinatorNode(show ${names.join(', ')})';
}

/// A `hide name1, name2, ...` combinator.
class HideCombinatorNode extends CombinatorNode {
  HideCombinatorNode({
    required this.keywordSpan,
    required List<String> names,
    required List<SourceSpan> nameSpans,
    required this.sourceSpan,
  })  : names = List.unmodifiable(names),
        nameSpans = List.unmodifiable(nameSpans),
        assert(
          names.length == nameSpans.length,
          'names and nameSpans must have the same length',
        );

  @override
  final SourceSpan keywordSpan;

  @override
  final List<String> names;

  @override
  final List<SourceSpan> nameSpans;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() => 'HideCombinatorNode(hide ${names.join(', ')})';
}
