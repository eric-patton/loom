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
