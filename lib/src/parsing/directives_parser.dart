import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart' hide ClassMember;

import '../model/directives.dart';
import '../model/source_span.dart';

/// Parses the top-level directives (`library`, `import`, `export`,
/// `part`, `part of`) of a Dart compilation unit into a
/// `CompilationUnitDirectives` model.
///
/// Unlike `parseWidgetTree` / `parseRouteTree` / `parseFunctionBody`,
/// this never throws — every Dart file has a (possibly empty) set of
/// directives. Source with analyzer parse errors still returns a
/// model with whatever directives were error-recoverable, plus a
/// non-empty `diagnostics` list.
CompilationUnitDirectives parseDirectives(String source) {
  final result = parseString(content: source, throwIfDiagnostics: false);
  final unit = result.unit;
  final diagnostics = <ParseDiagnostic>[
    for (final error in result.errors)
      ParseDiagnostic(
        span: SourceSpan(offset: error.offset, length: error.length),
        message: error.message,
      ),
  ];

  final directives = <DirectiveNode>[];
  for (final d in unit.directives) {
    final converted = _convertDirective(d, source);
    if (converted != null) directives.add(converted);
  }

  // Directive section end: just past the last directive's source span
  // (or the start of the first non-directive declaration). When the
  // file has no directives, anchor at offset 0.
  final sectionEnd = directives.isEmpty
      ? 0
      : directives.last.sourceSpan.offset + directives.last.sourceSpan.length;

  return CompilationUnitDirectives(
    directives: directives,
    directiveSectionEnd: sectionEnd,
    diagnostics: diagnostics,
  );
}

DirectiveNode? _convertDirective(Directive d, String source) {
  final span = SourceSpan(offset: d.offset, length: d.length);

  if (d is LibraryDirective) {
    final name = d.name;
    return LibraryDirectiveNode(
      libraryKeywordSpan: SourceSpan(
        offset: d.libraryKeyword.offset,
        length: d.libraryKeyword.length,
      ),
      name: name == null
          ? null
          : source.substring(name.offset, name.offset + name.length),
      nameSpan: name == null
          ? null
          : SourceSpan(offset: name.offset, length: name.length),
      sourceSpan: span,
    );
  }

  if (d is ImportDirective) {
    final uri = d.uri;
    final prefix = d.prefix;
    return ImportDirectiveNode(
      importKeywordSpan: SourceSpan(
        offset: d.importKeyword.offset,
        length: d.importKeyword.length,
      ),
      uri: _stripQuotes(source.substring(
        uri.offset,
        uri.offset + uri.length,
      )),
      uriSpan: SourceSpan(offset: uri.offset, length: uri.length),
      deferredKeywordSpan: d.deferredKeyword == null
          ? null
          : SourceSpan(
              offset: d.deferredKeyword!.offset,
              length: d.deferredKeyword!.length,
            ),
      asKeywordSpan: d.asKeyword == null
          ? null
          : SourceSpan(
              offset: d.asKeyword!.offset,
              length: d.asKeyword!.length,
            ),
      prefix: prefix?.name,
      prefixSpan: prefix == null
          ? null
          : SourceSpan(offset: prefix.offset, length: prefix.length),
      combinators: [
        for (final c in d.combinators) _convertCombinator(c, source),
      ],
      sourceSpan: span,
    );
  }

  if (d is ExportDirective) {
    final uri = d.uri;
    return ExportDirectiveNode(
      exportKeywordSpan: SourceSpan(
        offset: d.exportKeyword.offset,
        length: d.exportKeyword.length,
      ),
      uri: _stripQuotes(source.substring(
        uri.offset,
        uri.offset + uri.length,
      )),
      uriSpan: SourceSpan(offset: uri.offset, length: uri.length),
      combinators: [
        for (final c in d.combinators) _convertCombinator(c, source),
      ],
      sourceSpan: span,
    );
  }

  if (d is PartDirective) {
    final uri = d.uri;
    return PartDirectiveNode(
      partKeywordSpan: SourceSpan(
        offset: d.partKeyword.offset,
        length: d.partKeyword.length,
      ),
      uri: _stripQuotes(source.substring(
        uri.offset,
        uri.offset + uri.length,
      )),
      uriSpan: SourceSpan(offset: uri.offset, length: uri.length),
      sourceSpan: span,
    );
  }

  if (d is PartOfDirective) {
    final libraryName = d.libraryName;
    final uri = d.uri;
    return PartOfDirectiveNode(
      partKeywordSpan: SourceSpan(
        offset: d.partKeyword.offset,
        length: d.partKeyword.length,
      ),
      ofKeywordSpan: SourceSpan(
        offset: d.ofKeyword.offset,
        length: d.ofKeyword.length,
      ),
      libraryName: libraryName == null
          ? null
          : source.substring(
              libraryName.offset,
              libraryName.offset + libraryName.length,
            ),
      libraryNameSpan: libraryName == null
          ? null
          : SourceSpan(
              offset: libraryName.offset,
              length: libraryName.length,
            ),
      uri: uri == null
          ? null
          : _stripQuotes(
              source.substring(uri.offset, uri.offset + uri.length),
            ),
      uriSpan: uri == null
          ? null
          : SourceSpan(offset: uri.offset, length: uri.length),
      sourceSpan: span,
    );
  }

  // Unknown directive kind — skip (analyzer's UriBasedDirective is
  // covered above; new ones can be added later).
  return null;
}

CombinatorNode _convertCombinator(Combinator c, String source) {
  final span = SourceSpan(offset: c.offset, length: c.length);
  final keywordSpan = SourceSpan(
    offset: c.keyword.offset,
    length: c.keyword.length,
  );
  if (c is ShowCombinator) {
    final names = <String>[];
    final nameSpans = <SourceSpan>[];
    for (final n in c.shownNames) {
      names.add(n.name);
      nameSpans.add(SourceSpan(offset: n.offset, length: n.length));
    }
    return ShowCombinatorNode(
      keywordSpan: keywordSpan,
      names: names,
      nameSpans: nameSpans,
      sourceSpan: span,
    );
  }
  if (c is HideCombinator) {
    final names = <String>[];
    final nameSpans = <SourceSpan>[];
    for (final n in c.hiddenNames) {
      names.add(n.name);
      nameSpans.add(SourceSpan(offset: n.offset, length: n.length));
    }
    return HideCombinatorNode(
      keywordSpan: keywordSpan,
      names: names,
      nameSpans: nameSpans,
      sourceSpan: span,
    );
  }
  throw StateError('Unknown combinator type: ${c.runtimeType}');
}

String _stripQuotes(String literal) {
  if (literal.length >= 2 &&
      (literal.startsWith("'") || literal.startsWith('"'))) {
    return literal.substring(1, literal.length - 1);
  }
  return literal;
}
