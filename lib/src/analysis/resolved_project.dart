import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';

/// Optional resolved-analysis wrapper around analyzer's
/// `AnalysisContextCollection` (M10.2).
///
/// Loom's primary parsing path is `parseString` — fast, sync, and only
/// produces an unresolved AST. That covers most kernel ops because the
/// kernel reasons about source structure, not types. For the cases
/// where type information matters (precise rename, "what type is this
/// expression?", "is X assignable to Y?"), `ResolvedProject` provides
/// async access to fully-resolved analysis results backed by the
/// analyzer's full semantic pipeline.
///
/// Trade-offs vs. the unresolved path:
///   * **Heavier** — initializes a full analysis context; needs an
///     SDK on disk; reads `package_config.json` from the project.
///   * **Async** — `getResolvedUnit` returns a `Future`.
///   * **File-based** — `includedPaths` must be absolute paths on the
///     real filesystem. Use a temp directory for in-memory workflows.
///     `OverlayResourceProvider` integration is deferred — most
///     OutSystems-trajectory consumers will either write to a workspace
///     directory on disk (visual-editor save), or use the unresolved
///     path entirely.
///
/// Caller MUST call `dispose()` when done to release resources.
///
/// This class is opt-in — the rest of the kernel works without it.
class ResolvedProject {
  ResolvedProject._({
    required AnalysisContextCollection collection,
    required List<String> includedPaths,
  })  : _collection = collection,
        _includedPaths = includedPaths;

  /// Opens a `ResolvedProject` rooted at one or more directories or
  /// files. All paths must be absolute and normalized.
  ///
  /// [sdkPath] should be the absolute path to a Dart SDK installation
  /// (the directory containing `bin/dart` / `bin/dart.exe`). If null,
  /// the analyzer uses its default lookup logic (typically the SDK
  /// the host process is running on).
  static ResolvedProject open({
    required List<String> includedPaths,
    String? sdkPath,
  }) {
    final collection = AnalysisContextCollection(
      includedPaths: includedPaths,
      sdkPath: sdkPath,
    );
    return ResolvedProject._(
      collection: collection,
      includedPaths: includedPaths,
    );
  }

  final AnalysisContextCollection _collection;
  // ignore: unused_field
  final List<String> _includedPaths;

  /// Returns the fully-resolved unit for [filePath] (absolute path),
  /// or null if the file cannot be resolved (not in any context, has
  /// an invalid path, etc.). Diagnostics are available on the result.
  Future<ResolvedUnitResult?> getResolvedUnit(String filePath) async {
    final context = _collection.contextFor(filePath);
    final result = await context.currentSession.getResolvedUnit(filePath);
    return result is ResolvedUnitResult ? result : null;
  }

  /// Releases resources held by the underlying analysis context.
  /// MUST be called when done.
  Future<void> dispose() => _collection.dispose();
}
