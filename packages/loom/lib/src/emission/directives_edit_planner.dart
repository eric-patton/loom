import '../model/directives.dart';
import 'source_edit.dart';

/// Plans `SourceEdit`s for compilation-unit directive changes (M9.0a).
///
/// Operations:
///   * `addImport` — insert a new import directive into the import
///     section (sorted-ish — appended after last import or at top of
///     file if no imports exist).
///   * `removeDirective` — remove any directive (import/export/part/
///     library) including the trailing newline.
///   * `changeDirectiveUri` — replace the URI string of an import/
///     export/part directive.
///   * `changeImportPrefix` — replace the `as prefix` portion of an
///     import (works for both adding-to-existing and bare ops below).
///   * `addCombinatorName` — add a name to a show/hide combinator's
///     name list.
///   * `removeCombinatorName` — remove one name from a combinator.
///   * `addImportCombinator` — append a new show/hide combinator to
///     an import or export.
///
/// Add/remove for full combinators on an import are not yet
/// implemented at the combinator-source level for simplicity — use
/// `addImportCombinator` to append a new clause and
/// `addCombinatorName` / `removeCombinatorName` to edit individual
/// names.
class DirectivesEditPlanner {
  DirectivesEditPlanner._();

  // ----------------------- Add / remove directives ---------------

  /// Adds a new import directive to the compilation unit's import
  /// section. The new directive is appended after the last existing
  /// import (or after the library directive if no imports exist, or
  /// at the very top of the file otherwise).
  ///
  /// `newImportSource` should be a complete `import '...' [as p] [show
  /// ...] [hide ...] [deferred];` statement WITHOUT trailing newline.
  static SourceEdit addImport({
    required CompilationUnitDirectives unit,
    required String newImportSource,
    required String source,
  }) {
    // Find the best insertion point.
    final imports = unit.imports.toList();
    if (imports.isNotEmpty) {
      // After the last import — same indent, new line.
      final last = imports.last;
      return SourceEdit(
        offset: last.sourceSpan.offset + last.sourceSpan.length,
        length: 0,
        replacement: '\n$newImportSource',
      );
    }
    // No imports — anchor after the library directive if any.
    final libraryDirective =
        unit.directives.whereType<LibraryDirectiveNode>().firstOrNull;
    if (libraryDirective != null) {
      return SourceEdit(
        offset: libraryDirective.sourceSpan.offset +
            libraryDirective.sourceSpan.length,
        length: 0,
        replacement: '\n\n$newImportSource',
      );
    }
    // No directives at all — insert at the very top.
    return SourceEdit(
      offset: 0,
      length: 0,
      replacement: '$newImportSource\n',
    );
  }

  /// Removes a directive entirely, including the trailing newline.
  /// Same line-collapse pattern as `removeStatement` from M8.0a.
  static SourceEdit removeDirective({
    required DirectiveNode directive,
    required String source,
  }) {
    var start = directive.sourceSpan.offset;
    var end = directive.sourceSpan.offset + directive.sourceSpan.length;
    while (end < source.length) {
      final ch = source.codeUnitAt(end);
      if (ch == 0x20 || ch == 0x09 || ch == 0x0D) {
        end++;
      } else if (ch == 0x0A) {
        end++;
        break;
      } else {
        break;
      }
    }
    start = _trimLeadingIndentForFullLineRemoval(source, start);
    return SourceEdit(
      offset: start,
      length: end - start,
      replacement: '',
    );
  }

  /// See `class_structure_edit_planner.dart` for full rationale.
  /// Duplicated for the same reasons.
  static int _trimLeadingIndentForFullLineRemoval(String source, int start) {
    var probe = start;
    while (probe > 0) {
      final ch = source.codeUnitAt(probe - 1);
      if (ch == 0x20 || ch == 0x09) {
        probe--;
      } else {
        break;
      }
    }
    if (probe == 0 || source.codeUnitAt(probe - 1) == 0x0A) {
      return probe;
    }
    return start;
  }

  // ----------------------- Change directive fields ---------------

  /// Replaces the URI of an import, export, part, or part-of (URI
  /// form) directive. The new URI should NOT include surrounding
  /// quotes — they're preserved verbatim.
  ///
  /// Throws on a `LibraryDirective` (no URI) or a `PartOfDirective`
  /// in the dotted-name form (no URI).
  static SourceEdit changeDirectiveUri({
    required DirectiveNode directive,
    required String newUri,
  }) {
    final span = switch (directive) {
      ImportDirectiveNode() => directive.uriSpan,
      ExportDirectiveNode() => directive.uriSpan,
      PartDirectiveNode() => directive.uriSpan,
      PartOfDirectiveNode() => directive.uriSpan,
      LibraryDirectiveNode() => null,
    };
    if (span == null) {
      throw ArgumentError(
        'Directive has no URI to replace: ${directive.runtimeType}.',
      );
    }
    // Need to preserve the quote characters around the URI.
    // The uriSpan includes the quotes, so we replace only the inner
    // content. Subtract 2 from length, offset+1 from start.
    return SourceEdit(
      offset: span.offset + 1,
      length: span.length - 2,
      replacement: newUri,
    );
  }

  /// Replaces the `as prefix` portion of an import. The import MUST
  /// already have a prefix; throws otherwise (adding a prefix to a
  /// bare import is deferred — it requires inserting ` as <name>`).
  static SourceEdit changeImportPrefix({
    required ImportDirectiveNode import,
    required String newPrefix,
  }) {
    final span = import.prefixSpan;
    if (span == null) {
      throw ArgumentError(
        'Import has no prefix to replace. Adding a prefix to a bare '
        'import is not yet supported.',
      );
    }
    return SourceEdit(
      offset: span.offset,
      length: span.length,
      replacement: newPrefix,
    );
  }

  // ----------------------- Combinator edits ----------------------

  /// Adds a name to a combinator's name list. `index` 0 prepends;
  /// `names.length` appends.
  static SourceEdit addCombinatorName({
    required CombinatorNode combinator,
    required int index,
    required String newName,
  }) {
    if (index < 0 || index > combinator.names.length) {
      throw ArgumentError(
        'index $index out of range [0, ${combinator.names.length}]',
      );
    }
    if (combinator.names.isEmpty) {
      // `show ` / `hide ` with no names — append a name after the
      // keyword.
      return SourceEdit(
        offset: combinator.keywordSpan.offset + combinator.keywordSpan.length,
        length: 0,
        replacement: ' $newName',
      );
    }
    if (index == combinator.names.length) {
      final last = combinator.nameSpans.last;
      return SourceEdit(
        offset: last.offset + last.length,
        length: 0,
        replacement: ', $newName',
      );
    }
    final next = combinator.nameSpans[index];
    return SourceEdit(
      offset: next.offset,
      length: 0,
      replacement: '$newName, ',
    );
  }

  /// Removes a name from a combinator. The argument is the name's
  /// index in `combinator.names`. Handles comma + space cleanup.
  static SourceEdit removeCombinatorName({
    required CombinatorNode combinator,
    required int index,
    required String source,
  }) {
    if (index < 0 || index >= combinator.names.length) {
      throw ArgumentError(
        'index $index out of range [0, ${combinator.names.length})',
      );
    }
    var start = combinator.nameSpans[index].offset;
    var end =
        combinator.nameSpans[index].offset + combinator.nameSpans[index].length;
    if (combinator.names.length == 1) {
      // Sole name — caller probably wants to remove the whole
      // combinator instead. We just remove the name; the result may
      // produce a `show` / `hide` with nothing which won't parse.
      return SourceEdit(
        offset: start,
        length: end - start,
        replacement: '',
      );
    }
    if (index == combinator.names.length - 1) {
      // Last name — consume preceding comma + whitespace.
      var s = start;
      while (s > 0 &&
          (source.codeUnitAt(s - 1) == 0x20 ||
              source.codeUnitAt(s - 1) == 0x09)) {
        s--;
      }
      if (s > 0 && source.codeUnitAt(s - 1) == 0x2C) {
        s--;
      }
      start = s;
    } else {
      // Not last — consume trailing comma + whitespace.
      while (end < source.length && source.codeUnitAt(end) == 0x2C) {
        end++;
        while (end < source.length &&
            (source.codeUnitAt(end) == 0x20 ||
                source.codeUnitAt(end) == 0x09)) {
          end++;
        }
        break;
      }
    }
    return SourceEdit(
      offset: start,
      length: end - start,
      replacement: '',
    );
  }

  /// Appends a new `show` or `hide` combinator to an import or export
  /// directive. `newCombinatorSource` should be the complete clause
  /// (e.g. `'show foo, bar'`).
  static SourceEdit addImportCombinator({
    required ImportDirectiveNode import,
    required String newCombinatorSource,
  }) {
    // Insert just before the trailing `;`. The directive's
    // sourceSpan ends at the `;`'s position + 1, so the insertion
    // point is sourceSpan.offset + sourceSpan.length - 1.
    final semicolonOffset =
        import.sourceSpan.offset + import.sourceSpan.length - 1;
    return SourceEdit(
      offset: semicolonOffset,
      length: 0,
      replacement: ' $newCombinatorSource',
    );
  }

  /// Same as `addImportCombinator` but for an export.
  static SourceEdit addExportCombinator({
    required ExportDirectiveNode export,
    required String newCombinatorSource,
  }) {
    final semicolonOffset =
        export.sourceSpan.offset + export.sourceSpan.length - 1;
    return SourceEdit(
      offset: semicolonOffset,
      length: 0,
      replacement: ' $newCombinatorSource',
    );
  }
}
