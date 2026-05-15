import '../parsing/directives_parser.dart';
import 'directives.dart';

/// A modeled view of a Dart project — multiple files and the import
/// graph between them.
///
/// `ProjectModel` is the first multi-file model (M9.0b). It holds:
///   - A map of file paths → `ProjectFile` entries.
///   - Derived: the import graph (which file imports which).
///   - Derived: the export graph (which file exports which).
///
/// Construction: pass a map of file paths to source strings; the model
/// parses each file's directives. Paths are caller-defined strings —
/// the kernel doesn't enforce a particular file-system convention.
/// Callers can use absolute paths, relative paths, or whatever URI
/// scheme suits their needs.
///
/// Import URI resolution: the kernel does NOT resolve `package:` URIs
/// against a package config — that requires a build environment.
/// `ProjectModel` exposes the raw import URIs; resolving them to file
/// paths is the caller's job (typically via a `package_config.json`
/// reader).
class ProjectModel {
  ProjectModel._({
    required Map<String, ProjectFile> files,
  }) : files = Map.unmodifiable(files);

  /// Builds a `ProjectModel` from a map of file paths to source strings.
  ///
  /// Each file's directives are parsed at construction time. Parse
  /// diagnostics live on each `ProjectFile.directives.diagnostics`.
  factory ProjectModel.fromSources(Map<String, String> sources) {
    final files = <String, ProjectFile>{};
    for (final entry in sources.entries) {
      files[entry.key] = ProjectFile(
        path: entry.key,
        source: entry.value,
        directives: parseDirectives(entry.value),
      );
    }
    return ProjectModel._(files: files);
  }

  /// All files in the project keyed by path.
  final Map<String, ProjectFile> files;

  /// All files as an unordered iterable. Convenience.
  Iterable<ProjectFile> get allFiles => files.values;

  /// Returns the `ProjectFile` at [path], or null if absent.
  ProjectFile? operator [](String path) => files[path];

  /// Returns the set of file paths that import the file with [importerUri]
  /// from at least one of their imports. Uri matching is by string
  /// equality on `ImportDirectiveNode.uri` — no `package:` resolution.
  ///
  /// Use case: "who imports my-file.dart?". Pass the same URI string
  /// you'd write in an `import '...'` directive.
  Set<String> importersOf(String importerUri) {
    final out = <String>{};
    for (final file in files.values) {
      for (final imp in file.directives.imports) {
        if (imp.uri == importerUri) {
          out.add(file.path);
          break;
        }
      }
    }
    return out;
  }

  /// Returns the set of import URIs that THIS file imports.
  Set<String> importsFrom(String path) {
    final file = files[path];
    if (file == null) return const <String>{};
    return {for (final imp in file.directives.imports) imp.uri};
  }

  /// The total number of import directives across all files.
  int get totalImports {
    var n = 0;
    for (final f in files.values) {
      n += f.directives.imports.length;
    }
    return n;
  }

  /// Files that have at least one parse diagnostic (i.e. their source
  /// has syntax errors the analyzer reported).
  Iterable<ProjectFile> get filesWithDiagnostics =>
      files.values.where((f) => f.directives.diagnostics.isNotEmpty);

  @override
  String toString() => 'ProjectModel(${files.length} file(s))';
}

/// A single file in a `ProjectModel`. Holds the path, the source
/// string, and the parsed directives.
///
/// Note: only directives are pre-parsed (M9.0b scope). Other per-file
/// models (widget tree, class structure, function body) are parsed
/// on demand by callers using the M5–M8 parsers.
class ProjectFile {
  const ProjectFile({
    required this.path,
    required this.source,
    required this.directives,
  });

  /// Caller-supplied path/key for this file.
  final String path;

  /// Raw source bytes.
  final String source;

  /// Parsed directives (M9.0a).
  final CompilationUnitDirectives directives;

  @override
  String toString() => 'ProjectFile($path)';
}
