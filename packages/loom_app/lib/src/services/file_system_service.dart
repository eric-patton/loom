import 'dart:io';

import 'package:path/path.dart' as p;

/// A snapshot of a project read from disk: canonical-URI → source plus a
/// reverse map from URI back to the native filesystem path. Tabs and the
/// kernel index off the URI; file I/O uses the native path.
class ProjectSnapshot {
  const ProjectSnapshot({
    required this.rootPath,
    required this.sources,
    required this.uriToPath,
  });

  /// The directory the project was loaded from.
  final String rootPath;

  /// Keyed by `Uri.file(absoluteCanonicalPath).toString()`.
  final Map<String, String> sources;

  /// `kernelUri → nativeAbsolutePath`. Used to write edits back to disk.
  final Map<String, String> uriToPath;

  /// Native path for the document keyed by [uri], or null if unknown.
  String? pathFor(String uri) => uriToPath[uri];

  /// Iteration helper for the file list.
  Iterable<String> get uris => sources.keys;
}

/// Reads Dart project sources from disk and writes single-file edits
/// atomically. Stateless; all callers go through the same instance via
/// `fileSystemServiceProvider`.
class FileSystemService {
  const FileSystemService();

  /// Walks [rootPath] recursively and reads every `.dart` file that is
  /// not under an excluded directory (`.dart_tool/`, `build/`, `.git/`).
  /// Returns the canonical URI map ready to hand to the kernel.
  Future<ProjectSnapshot> readProject(String rootPath) async {
    final root = Directory(rootPath);
    if (!root.existsSync()) {
      throw FileSystemException('Project root not found', rootPath);
    }
    final entries = await root.list(recursive: true).toList();
    final sources = <String, String>{};
    final uriToPath = <String, String>{};
    for (final entity in entries) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.dart')) continue;
      if (_isExcluded(entity.path, rootPath)) continue;
      final absolute = p.canonicalize(entity.absolute.path);
      final uri = Uri.file(absolute).toString();
      sources[uri] = await entity.readAsString();
      uriToPath[uri] = absolute;
    }
    return ProjectSnapshot(
      rootPath: p.canonicalize(rootPath),
      sources: sources,
      uriToPath: uriToPath,
    );
  }

  /// Reads a single Dart file. Used after an edit to confirm the saved
  /// source on disk matches what the editor thinks is there.
  Future<String> readFile(String path) async => File(path).readAsString();

  /// Writes [contents] to [path] atomically via a sibling `.tmp` file
  /// and rename. Prevents partial writes from leaving a corrupted file
  /// on a crash mid-write.
  Future<void> saveAtomic(String path, String contents) async {
    final temp =
        File('$path.loom-tmp-${DateTime.now().microsecondsSinceEpoch}');
    await temp.writeAsString(contents, flush: true);
    if (await File(path).exists()) {
      await File(path).delete();
    }
    await temp.rename(path);
  }

  bool _isExcluded(String filePath, String rootPath) {
    final rel = p.relative(filePath, from: rootPath);
    for (final part in p.split(rel)) {
      if (part == '.dart_tool' || part == 'build' || part == '.git') {
        return true;
      }
    }
    return false;
  }
}
