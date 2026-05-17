import 'package:analyzer/dart/analysis/utilities.dart';

import '../catalog/widget_catalog.dart';
import '../model/directives.dart';
import '../model/project.dart';
import 'project_widget_discovery.dart';

/// Project-wide index of `extends *Widget` classes across every file in a
/// `ProjectModel`. Built once per project (eagerly), then consulted by the
/// widget parser to recognize user widgets that are declared in one file
/// and referenced from another.
///
/// Phase 5 of the opaque-root attack: Phase 1's intra-file discovery and
/// Phase 2's slot inference covered widgets defined and used in the same
/// file. Real apps split widgets across many files (`AppBar` in
/// `app_bar.dart`, `HomePage` in `home_page.dart`, etc.) — this index
/// closes that gap.
///
/// The construction cost is O(files × class-declarations-per-file). For
/// typical projects (<500 files) it's negligible; the result is cached on
/// the [ProjectWidgetIndex] instance and amortized across every
/// `parseWidgetTree` call that consults it.
///
/// Visibility rules (mirror Dart's import semantics):
///   * A widget declared in file Y is visible from file X iff X imports Y
///     (directly or via a barrel that re-exports Y).
///   * `import 'foo.dart' show MyWidget;` — only `MyWidget` is visible.
///   * `import 'foo.dart' hide MyWidget;` — `MyWidget` is excluded.
///   * `import 'foo.dart' as f;` (prefixed imports) — **skipped**. The
///     widget reference `f.MyWidget(...)` parses as a named constructor
///     (`Class.name(...)` shape), not a top-level widget; recognizing it
///     would need a separate code path. Deferred.
///   * Transitive re-exports: file A `export 'b.dart'` makes B's widgets
///     visible to anyone importing A.
class ProjectWidgetIndex {
  ProjectWidgetIndex._({
    required Map<String, Map<String, WidgetSpec>> widgetsPerFile,
    required ProjectModel project,
  })  : _widgetsPerFile = widgetsPerFile,
        _project = project;

  /// Walks every file in [project] and records its `extends *Widget`
  /// classes with their inferred specs.
  factory ProjectWidgetIndex.build(ProjectModel project) {
    final widgetsPerFile = <String, Map<String, WidgetSpec>>{};
    for (final entry in project.files.entries) {
      // `throwIfDiagnostics: false` keeps the index tolerant of files with
      // syntax errors — matches the rest of the kernel's "degrade gracefully"
      // posture and `ProjectModel.fromSources`' own behavior. Without it, a
      // single malformed file in the project crashes the index build.
      final unit = parseString(
        content: entry.value.source,
        throwIfDiagnostics: false,
      ).unit;
      final widgets = discoverIntraFileWidgets(unit);
      if (widgets.isNotEmpty) {
        widgetsPerFile[entry.key] = widgets;
      }
    }
    return ProjectWidgetIndex._(
      widgetsPerFile: widgetsPerFile,
      project: project,
    );
  }

  /// Rebuilds the index for a single file's new source, sharing every
  /// other file's already-computed widget map with the returned index.
  ///
  /// Use case: a visual editor that edits one file at a time can call
  /// this on every save / debounced edit instead of paying the
  /// `ProjectWidgetIndex.build` cost (which scans every file in the
  /// project) per keystroke. The returned index keeps the same
  /// underlying `ProjectModel` reference, so callers must keep that
  /// model in sync separately — typically by also recreating it from
  /// updated sources before rebuilding the index against the new model.
  ///
  /// [filePath] is canonicalized so callers can pass raw Windows paths,
  /// POSIX paths, or `file:///` URIs interchangeably.
  ///
  /// If [filePath] is not present in the project, the returned index
  /// drops the file's existing widgets (if any) but is otherwise
  /// identical — the same semantics as if the file was deleted.
  ProjectWidgetIndex rebuildFile(String filePath, String newSource) {
    final canonical = canonicalizeFileKey(filePath);
    // Re-parse the single file's widgets.
    final unit = parseString(
      content: newSource,
      throwIfDiagnostics: false,
    ).unit;
    final widgets = discoverIntraFileWidgets(unit);
    // Share every other entry; replace this file's entry with the new map
    // (or drop it if the new file has no widgets).
    final updated = <String, Map<String, WidgetSpec>>{
      ..._widgetsPerFile,
    };
    if (widgets.isEmpty) {
      updated.remove(canonical);
    } else {
      updated[canonical] = widgets;
    }
    return ProjectWidgetIndex._(
      widgetsPerFile: updated,
      project: _project,
    );
  }

  final Map<String, Map<String, WidgetSpec>> _widgetsPerFile;
  final ProjectModel _project;

  /// Widgets declared directly in [filePath] (without considering
  /// re-exports from other files). Convenience accessor. [filePath]
  /// is canonicalized.
  Map<String, WidgetSpec> widgetsIn(String filePath) =>
      _widgetsPerFile[canonicalizeFileKey(filePath)] ??
      const <String, WidgetSpec>{};

  /// Widgets visible from [filePath] via its imports — intended for the
  /// parser's `localCatalog` fallback. Intra-file widgets are NOT
  /// included here (the parser already discovers those independently);
  /// only widgets imported from other project files appear in this map.
  /// [filePath] is canonicalized.
  Map<String, WidgetSpec> widgetsVisibleFrom(String filePath) {
    final canonicalFrom = canonicalizeFileKey(filePath);
    final result = <String, WidgetSpec>{};
    final file = _project.files[canonicalFrom];
    if (file == null) return result;

    for (final imp in file.directives.imports) {
      // Prefixed imports require qualified references (`f.MyWidget(...)`)
      // which the parser classifies as named constructors. Cross-file
      // resolution for that shape is a separate fix; skip here.
      if (imp.prefix != null) continue;

      final resolvedUri =
          _project.resolveImportUri(imp.uri, fromFile: canonicalFrom);
      if (resolvedUri == null) continue;
      final targetPath = canonicalizeFileKey(resolvedUri.toString());
      if (!_project.files.containsKey(targetPath)) continue;

      final exported = _widgetsExportedBy(targetPath, <String>{});
      final filtered = _applyCombinators(exported, imp.combinators);
      result.addAll(filtered);
    }

    return result;
  }

  /// Widgets that file [path] exposes to consumers — its own declarations
  /// plus widgets transitively re-exported through `export 'foo.dart';`
  /// directives. Cycle-safe.
  ///
  /// `visited` is the chain of paths currently being traversed (used for
  /// cycle detection). It is COPIED at every recursive call, not shared,
  /// so a diamond chain (A re-exports through both B and D into C with
  /// different combinators) doesn't suppress the second branch — both
  /// branches must walk through C independently to apply their own
  /// combinators correctly.
  Map<String, WidgetSpec> _widgetsExportedBy(
    String path,
    Set<String> visited,
  ) {
    if (visited.contains(path)) return const <String, WidgetSpec>{};

    final result = <String, WidgetSpec>{...?_widgetsPerFile[path]};

    final file = _project.files[path];
    if (file == null) return result;

    final nextVisited = {...visited, path};
    for (final exp in file.directives.exports) {
      final resolvedUri = _project.resolveImportUri(exp.uri, fromFile: path);
      if (resolvedUri == null) continue;
      final targetPath = canonicalizeFileKey(resolvedUri.toString());
      final reExported = _widgetsExportedBy(targetPath, nextVisited);
      final filtered = _applyCombinators(reExported, exp.combinators);
      result.addAll(filtered);
    }

    return result;
  }

  static Map<String, WidgetSpec> _applyCombinators(
    Map<String, WidgetSpec> widgets,
    List<CombinatorNode> combinators,
  ) {
    if (combinators.isEmpty) return widgets;
    final result = <String, WidgetSpec>{};
    for (final entry in widgets.entries) {
      if (_namePassesCombinators(entry.key, combinators)) {
        result[entry.key] = entry.value;
      }
    }
    return result;
  }

  static bool _namePassesCombinators(
    String name,
    List<CombinatorNode> combinators,
  ) {
    for (final c in combinators) {
      if (c is ShowCombinatorNode) {
        if (!c.names.contains(name)) return false;
      } else if (c is HideCombinatorNode) {
        if (c.names.contains(name)) return false;
      }
    }
    return true;
  }
}
