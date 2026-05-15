import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart' hide ClassMember;
import 'package:analyzer/dart/ast/visitor.dart';

import '../model/project.dart';
import 'directives_edit_planner.dart';
import 'source_edit.dart';

/// A bundle of `SourceEdit`s spanning multiple files.
///
/// Keys are file paths (using the same string scheme `ProjectModel`
/// uses — caller-defined). Values are lists of edits to apply to that
/// file's source. Files not present in the map are unmodified.
///
/// `applyProjectEdits` applies a `ProjectEdits` to a `Map<String,
/// String>` of file sources, returning a new map of post-edit sources.
typedef ProjectEdits = Map<String, List<SourceEdit>>;

/// Applies a `ProjectEdits` to a map of file sources, returning a new
/// map with the edited contents. Files not mentioned in `edits` are
/// passed through unchanged.
Map<String, String> applyProjectEdits(
  Map<String, String> sources,
  ProjectEdits edits,
) {
  final out = <String, String>{};
  for (final entry in sources.entries) {
    final fileEdits = edits[entry.key];
    out[entry.key] = fileEdits == null
        ? entry.value
        : applySourceEdits(entry.value, fileEdits);
  }
  return out;
}

/// Plans `ProjectEdits` for cross-file changes (M9.1).
///
/// These are "broadcast" ops — they match by URI string only and
/// don't require symbol resolution (that's M9.3+). Useful for
/// migrations like:
///   * "Rename every `package:old/api.dart` import to
///     `package:new/api.dart`."
///   * "Remove every `import 'dart:io';` from the project (e.g.
///     when moving to a web build)."
///   * "Add `import 'package:my/logging.dart';` to every file in
///     `lib/`."
///
/// `ProjectModel` is the input. The output `ProjectEdits` can be
/// applied via `applyProjectEdits` (atomically) or per-file via the
/// kernel's existing `applySourceEdits`.
class ProjectEditPlanner {
  ProjectEditPlanner._();

  /// Adds an import directive to every file in [project] matching the
  /// optional [where] predicate. Files that already import `uri` are
  /// SKIPPED (no duplicate imports).
  ///
  /// `newImportSource` should be a complete `import '...' [as p]
  /// [show ...] [hide ...] [deferred];` statement WITHOUT trailing
  /// newline.
  ///
  /// Pass `uri` to enable de-duplication — the planner checks each
  /// file's existing imports against this URI and skips files that
  /// already import it.
  static ProjectEdits addImportEverywhere({
    required ProjectModel project,
    required String newImportSource,
    required String uri,
    bool Function(ProjectFile file)? where,
  }) {
    final out = <String, List<SourceEdit>>{};
    for (final file in project.allFiles) {
      if (where != null && !where(file)) continue;
      // Skip if file already imports this URI.
      final alreadyHas = file.directives.imports.any((imp) => imp.uri == uri);
      if (alreadyHas) continue;
      out[file.path] = [
        DirectivesEditPlanner.addImport(
          unit: file.directives,
          newImportSource: newImportSource,
          source: file.source,
        ),
      ];
    }
    return out;
  }

  /// Removes every import directive across the project whose URI
  /// matches [uri]. Each file gets one edit per matching import.
  static ProjectEdits removeImportEverywhere({
    required ProjectModel project,
    required String uri,
  }) {
    final out = <String, List<SourceEdit>>{};
    for (final file in project.allFiles) {
      final matches =
          file.directives.imports.where((imp) => imp.uri == uri).toList();
      if (matches.isEmpty) continue;
      out[file.path] = [
        for (final imp in matches)
          DirectivesEditPlanner.removeDirective(
            directive: imp,
            source: file.source,
          ),
      ];
    }
    return out;
  }

  /// Renames every import URI matching [oldUri] to [newUri] across
  /// all files in the project. Useful for migrations like
  /// `package:old/api.dart` → `package:new/api.dart`.
  ///
  /// Quote style is preserved per file (`changeDirectiveUri` handles
  /// the quote-preserving substitution).
  static ProjectEdits renameImportUri({
    required ProjectModel project,
    required String oldUri,
    required String newUri,
  }) {
    final out = <String, List<SourceEdit>>{};
    for (final file in project.allFiles) {
      final matches =
          file.directives.imports.where((imp) => imp.uri == oldUri).toList();
      if (matches.isEmpty) continue;
      out[file.path] = [
        for (final imp in matches)
          DirectivesEditPlanner.changeDirectiveUri(
            directive: imp,
            newUri: newUri,
          ),
      ];
    }
    return out;
  }

  // ----------------------- Project-wide rename (M9.4) ------------

  /// Renames a top-level declaration AND all `SimpleIdentifier`
  /// references to it across every file that imports the declaring
  /// file (directly or via re-exports). Also updates `show` / `hide`
  /// combinator names that mention the old name.
  ///
  /// Returns `ProjectEdits` covering every file that needs to change.
  /// Apply via `applyProjectEdits`.
  ///
  /// Limitations (matching M8.0h / M8.9 symbol-aware rename ops):
  ///   * Identifier-only matching — string literals and comments
  ///     containing the name are NOT renamed.
  ///   * No shadow detection — if a file has a local variable with
  ///     the same name as the renamed top-level symbol, this op
  ///     renames BOTH. Caller-responsible.
  ///   * The kernel doesn't know which references resolve to the
  ///     specific target symbol vs. a same-named symbol from a
  ///     different import. We rename all identifiers matching by
  ///     name in files that have the symbol in scope. False
  ///     positives possible in projects with name collisions.
  ///   * `dart:*` and packages without a `packageConfig` entry
  ///     aren't checked — files importing those don't get edits
  ///     unless they appear in `project.files`.
  static ProjectEdits renameTopLevelDeclaration({
    required ProjectModel project,
    required SymbolLocation symbol,
    required String newName,
  }) {
    final oldName = symbol.name;
    final out = <String, List<SourceEdit>>{};

    // 1. Edit at the declaration site (rename the name token).
    out[symbol.filePath] = [
      SourceEdit(
        offset: symbol.declarationNameSpan.offset,
        length: symbol.declarationNameSpan.length,
        replacement: newName,
      ),
    ];

    // 2. Within the declaration file, rename all internal references.
    final declFile = project[symbol.filePath]!;
    _collectFileReferenceEdits(
      file: declFile,
      oldName: oldName,
      newName: newName,
      excludeOffset: symbol.declarationNameSpan.offset,
      out: out,
    );

    // 3. For every OTHER file that REACHES the symbol's file via an
    //    import or export — directly or transitively — walk it and
    //    rename references. "Reaches" instead of "in scope" so
    //    `hide Foo` clauses (which suppress visibility) still get
    //    rewritten.
    for (final file in project.allFiles) {
      if (file.path == symbol.filePath) continue;
      if (!_fileReachesSymbol(file, symbol.filePath, oldName, project)) {
        continue;
      }
      _collectFileReferenceEdits(
        file: file,
        oldName: oldName,
        newName: newName,
        excludeOffset: null,
        out: out,
      );
    }

    // Sort each file's edits by offset for clean applySourceEdits.
    for (final entry in out.entries) {
      entry.value.sort((a, b) => a.offset.compareTo(b.offset));
    }
    return out;
  }

  /// True iff [file] has at least one import or export directive
  /// that reaches [targetFile] (directly) or reaches a file that
  /// re-exports [oldName]. Used by `renameTopLevelDeclaration` to
  /// decide which files to scan for references — broader than
  /// "in scope" so `hide` clauses still get rewritten.
  static bool _fileReachesSymbol(
    ProjectFile file,
    String targetFile,
    String oldName,
    ProjectModel project,
  ) {
    for (final imp in file.directives.imports) {
      final resolved =
          project.resolveImportUri(imp.uri, fromFile: file.path)?.toString();
      if (resolved == null) continue;
      if (resolved == targetFile) return true;
      if (project.exportedNamesOf(resolved).contains(oldName)) return true;
    }
    for (final exp in file.directives.exports) {
      final resolved =
          project.resolveImportUri(exp.uri, fromFile: file.path)?.toString();
      if (resolved == null) continue;
      if (resolved == targetFile) return true;
      if (project.exportedNamesOf(resolved).contains(oldName)) return true;
    }
    return false;
  }

  static void _collectFileReferenceEdits({
    required ProjectFile file,
    required String oldName,
    required String newName,
    int? excludeOffset,
    required Map<String, List<SourceEdit>> out,
  }) {
    final result = parseString(content: file.source, throwIfDiagnostics: false);
    final visitor = _ProjectIdentifierCollector(target: oldName);
    result.unit.accept(visitor);

    final edits = <SourceEdit>[];
    final seenOffsets = <int>{};
    for (final m in visitor.matches) {
      if (excludeOffset != null && m.offset == excludeOffset) continue;
      if (!seenOffsets.add(m.offset)) continue;
      edits.add(SourceEdit(
        offset: m.offset,
        length: m.length,
        replacement: newName,
      ));
    }

    if (edits.isNotEmpty) {
      out.putIfAbsent(file.path, () => []).addAll(edits);
    }
  }

  /// Merges two `ProjectEdits` maps. When both maps have edits for
  /// the same file, the lists are concatenated. The caller is
  /// responsible for ensuring the resulting edits don't overlap
  /// (`applySourceEdits` will throw otherwise).
  static ProjectEdits merge(ProjectEdits a, ProjectEdits b) {
    final out = <String, List<SourceEdit>>{};
    for (final entry in a.entries) {
      out[entry.key] = [...entry.value];
    }
    for (final entry in b.entries) {
      final existing = out[entry.key];
      if (existing == null) {
        out[entry.key] = [...entry.value];
      } else {
        out[entry.key] = [...existing, ...entry.value];
      }
    }
    return out;
  }
}

/// A match for a name-token reference — captures just offset + length
/// so the same record represents either a `SimpleIdentifier` (from
/// regular expression references) or a `NamedType.name` token (from
/// type references in declarations / parameters / extends clauses).
typedef _NameMatch = ({int offset, int length});

/// AST visitor collecting reference-token offsets matching [target].
/// Used by `renameTopLevelDeclaration`.
///
/// Covers two AST positions:
///   * `SimpleIdentifier` nodes — regular expression references,
///     method invocations, property names, show/hide combinator
///     names.
///   * `NamedType.name` tokens — type references in field/parameter/
///     return types, extends/implements/with clauses.
///
/// Excludes string-literal contents and comment text (not tokens
/// the visitor visits).
class _ProjectIdentifierCollector extends RecursiveAstVisitor<void> {
  _ProjectIdentifierCollector({required this.target});

  final String target;
  final List<_NameMatch> matches = [];

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.name == target) {
      matches.add((offset: node.offset, length: node.length));
    }
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitNamedType(NamedType node) {
    if (node.name.lexeme == target) {
      matches.add((offset: node.name.offset, length: node.name.length));
    }
    super.visitNamedType(node);
  }
}
