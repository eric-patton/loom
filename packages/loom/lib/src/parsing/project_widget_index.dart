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
      final unit = parseString(content: entry.value.source).unit;
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

  final Map<String, Map<String, WidgetSpec>> _widgetsPerFile;
  final ProjectModel _project;

  /// Widgets declared directly in [filePath] (without considering
  /// re-exports from other files). Convenience accessor.
  Map<String, WidgetSpec> widgetsIn(String filePath) =>
      _widgetsPerFile[filePath] ?? const <String, WidgetSpec>{};

  /// Widgets visible from [filePath] via its imports — intended for the
  /// parser's `localCatalog` fallback. Intra-file widgets are NOT
  /// included here (the parser already discovers those independently);
  /// only widgets imported from other project files appear in this map.
  Map<String, WidgetSpec> widgetsVisibleFrom(String filePath) {
    final result = <String, WidgetSpec>{};
    final file = _project.files[filePath];
    if (file == null) return result;

    for (final imp in file.directives.imports) {
      // Prefixed imports require qualified references (`f.MyWidget(...)`)
      // which the parser classifies as named constructors. Cross-file
      // resolution for that shape is a separate fix; skip here.
      if (imp.prefix != null) continue;

      final resolvedUri =
          _project.resolveImportUri(imp.uri, fromFile: filePath);
      if (resolvedUri == null) continue;
      final targetPath = resolvedUri.toString();
      if (!_project.files.containsKey(targetPath)) continue;

      final exported = _widgetsExportedBy(targetPath, <String>{});
      final filtered = _applyCombinators(exported, imp.combinators);
      result.addAll(filtered);
    }

    return result;
  }

  /// Widgets that file [path] exposes to consumers — its own declarations
  /// plus widgets transitively re-exported through `export 'foo.dart';`
  /// directives. Cycle-safe via the [visited] set.
  Map<String, WidgetSpec> _widgetsExportedBy(
    String path,
    Set<String> visited,
  ) {
    if (visited.contains(path)) return const <String, WidgetSpec>{};
    visited.add(path);

    final result = <String, WidgetSpec>{...?_widgetsPerFile[path]};

    final file = _project.files[path];
    if (file == null) return result;

    for (final exp in file.directives.exports) {
      final resolvedUri = _project.resolveImportUri(exp.uri, fromFile: path);
      if (resolvedUri == null) continue;
      final targetPath = resolvedUri.toString();
      final reExported = _widgetsExportedBy(targetPath, visited);
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
