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
      uri: _decodeUriLiteral(uri, source),
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
      uri: _decodeUriLiteral(uri, source),
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
      uri: _decodeUriLiteral(uri, source),
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
      uri: uri == null ? null : _decodeUriLiteral(uri, source),
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

/// Returns the decoded URI string for a directive URI literal.
///
/// Prefers the analyzer's already-decoded `SimpleStringLiteral.value` —
/// it handles raw (`r'...'`) and triple-quoted (`'''...'''` / `"""..."""`)
/// forms, plus escape sequences, correctly. Falls back to a substring
/// strip for non-`SimpleStringLiteral` shapes (`AdjacentStrings`,
/// `StringInterpolation`) which aren't valid URIs but might appear in
/// malformed/error-recovered source.
String _decodeUriLiteral(StringLiteral uri, String source) {
  if (uri is SimpleStringLiteral) {
    return uri.value;
  }
  // Defensive fallback: strip outermost single or double quotes (any count).
  // Real directive URIs are always SimpleStringLiteral so this rarely runs.
  final raw = source.substring(uri.offset, uri.offset + uri.length);
  return _stripOuterQuotes(raw);
}

String _stripOuterQuotes(String literal) {
  if (literal.isEmpty) return literal;
  // Match opening quote run (`'`, `'''`, `"`, `"""`, with optional `r` prefix).
  var start = 0;
  if (literal.startsWith('r')) {
    start = 1;
  }
  if (start >= literal.length) return literal;
  final ch = literal[start];
  if (ch != "'" && ch != '"') return literal;
  // Count run.
  var run = 0;
  while (start + run < literal.length && literal[start + run] == ch) {
    run++;
  }
  if (run >= 3) run = 3;
  // Strip `run` chars from start and end.
  if (literal.length < start + run + run) return literal;
  return literal.substring(start + run, literal.length - run);
}
