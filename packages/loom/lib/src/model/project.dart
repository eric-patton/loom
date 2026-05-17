import 'package:path/path.dart' as p;

import '../parsing/directives_parser.dart';
import '../parsing/file_symbols_parser.dart';
import 'directives.dart';
import 'file_symbols.dart';
import 'package_config.dart';
import 'source_span.dart';

/// Canonicalizes a caller-supplied file key to a URI form the kernel can
/// reason about consistently.
///
/// Why this exists: `Uri.parse(r'C:\repos\app\lib\main.dart')` succeeds but
/// interprets `C` as a one-letter URI scheme, leaving the path with
/// backslashes the URI resolver treats as opaque. Resolving a relative
/// import (`'helper.dart'`) against such a "URI" silently produces
/// `c:helper.dart` instead of the actual sibling file, so cross-file
/// resolution breaks invisibly on Windows. Fixing the kernel to canonicalize
/// at every entry point means callers can pass keys in any form
/// (raw Windows path, raw POSIX path, `file:///` URI, relative path) and
/// the model stores and looks them up consistently.
///
/// Rules:
///   * URI strings with a multi-char scheme (`file:`, `package:`, `dart:`,
///     `https:`) — returned as-is.
///   * Absolute paths (Windows `C:\foo` / `C:/foo`, POSIX `/foo`,
///     UNC `\\server\share\foo`) — converted to a `file:///` URI via
///     `path.toUri`.
///   * Relative paths (`lib/main.dart`, `helper.dart`, also Windows-style
///     `lib\helper.dart`) — backslashes are folded to forward slashes and
///     the path is normalized, but no scheme is added; the result is still
///     a relative URI string.
String canonicalizeFileKey(String key) {
  final parsed = Uri.tryParse(key);
  // `parsed.scheme.length > 1` filters out the Windows-drive-letter
  // false positive — `C:foo` parses with scheme `c`, length 1. Real
  // URI schemes (`file`, `package`, `dart`, `http`, `https`) are all
  // length >= 4, so this threshold is safe.
  if (parsed != null && parsed.hasScheme && parsed.scheme.length > 1) {
    return parsed.toString();
  }
  // Filesystem path. Use the platform's path context — on Windows this
  // handles drive letters and backslashes; on POSIX it handles forward
  // slashes. p.toUri produces a `file:///` URI for absolute paths and a
  // relative URI for relative paths.
  return p.toUri(p.normalize(key)).toString();
}

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
    required this.packageConfig,
  }) : files = Map.unmodifiable(files);

  /// Builds a `ProjectModel` from a map of file paths to source strings.
  ///
  /// Each file's directives are parsed at construction time. Parse
  /// diagnostics live on each `ProjectFile.directives.diagnostics`.
  ///
  /// Optionally pass a [packageConfig] to enable `package:` URI
  /// resolution via `resolveImportUri`. Without one, `package:` URIs
  /// can't be resolved (relative URIs still work).
  factory ProjectModel.fromSources(
    Map<String, String> sources, {
    PackageConfig? packageConfig,
  }) {
    final files = <String, ProjectFile>{};
    for (final entry in sources.entries) {
      final canonical = canonicalizeFileKey(entry.key);
      files[canonical] = ProjectFile(
        path: canonical,
        source: entry.value,
        directives: parseDirectives(entry.value),
      );
    }
    return ProjectModel._(
      files: files,
      packageConfig: packageConfig ?? PackageConfig.empty(),
    );
  }

  /// All files in the project keyed by path.
  final Map<String, ProjectFile> files;

  /// Package configuration for `package:` URI resolution. Defaults
  /// to `PackageConfig.empty()`.
  final PackageConfig packageConfig;

  /// All files as an unordered iterable. Convenience.
  Iterable<ProjectFile> get allFiles => files.values;

  /// Returns the `ProjectFile` at [path], or null if absent. [path] is
  /// canonicalized — callers can pass raw Windows paths, POSIX paths, or
  /// `file:///` URIs interchangeably.
  ProjectFile? operator [](String path) => files[canonicalizeFileKey(path)];

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
    final file = files[canonicalizeFileKey(path)];
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

  /// Computes the SET of top-level names that [path] exports to its
  /// consumers — directly-declared names PLUS names re-exported via
  /// `export 'foo.dart';` (transitively, with show/hide combinators
  /// applied).
  ///
  /// Cycle-safe: if A exports B and B exports A, the recursion is
  /// bounded by a visited set.
  Set<String> exportedNamesOf(String path) {
    return _exportedNamesOf(canonicalizeFileKey(path), <String>{});
  }

  Set<String> _exportedNamesOf(String path, Set<String> visited) {
    if (visited.contains(path)) return const <String>{};
    final file = files[path];
    if (file == null) return const <String>{};
    final names = <String>{...file.symbols.names};
    // Copy the visited set at each recursive call rather than sharing it
    // across branches. A diamond chain (A re-exports through both B and D
    // into C, with different combinators) needs both branches to walk
    // through C independently and apply their own combinators; sharing
    // would suppress the second branch.
    final nextVisited = {...visited, path};
    for (final exp in file.directives.exports) {
      final resolvedUri = resolveImportUri(exp.uri, fromFile: path)?.toString();
      if (resolvedUri == null) continue;
      // Find the project file at the resolved URI.
      final targetPath = _findFileByUriString(resolvedUri);
      if (targetPath == null) continue;
      final reExported = _exportedNamesOf(targetPath, nextVisited);
      names.addAll(_applyCombinators(reExported, exp.combinators));
    }
    return names;
  }

  /// Resolves a top-level symbol [name] as seen from [fromFile]. Walks
  /// the file's imports (with show/hide and prefix) and returns the
  /// `SymbolLocation` of the original declaration, or null if the
  /// name isn't in scope.
  ///
  /// Doesn't handle:
  ///   - Symbols from `dart:*` URIs (the kernel doesn't know SDK
  ///     contents).
  ///   - Symbols from packages whose roots aren't in `packageConfig`
  ///     or whose files aren't in `files`.
  ///   - Local-scope names (function parameters, local vars).
  SymbolLocation? resolveSymbol(String name, {required String fromFile}) {
    final canonicalFrom = canonicalizeFileKey(fromFile);
    final file = files[canonicalFrom];
    if (file == null) return null;

    // First, check if the file itself declares the name.
    final ownDecl = file.symbols.findDeclaration(name);
    if (ownDecl != null) {
      return SymbolLocation(
        filePath: canonicalFrom,
        name: name,
        declarationNameSpan: ownDecl.nameSpan,
        declarationSpan: ownDecl.declarationSpan,
        kind: ownDecl.kind,
      );
    }

    // Otherwise, walk imports.
    for (final imp in file.directives.imports) {
      // If the import has a prefix, the unprefixed name isn't visible
      // from this import.
      if (imp.prefix != null) continue;

      final resolvedUri =
          resolveImportUri(imp.uri, fromFile: canonicalFrom)?.toString();
      if (resolvedUri == null) continue;
      final targetPath = _findFileByUriString(resolvedUri);
      if (targetPath == null) continue;

      // Check if the name passes the import's combinators.
      if (!_namePassesCombinators(name, imp.combinators)) continue;

      // Check if the imported file actually exports this name.
      final exported = exportedNamesOf(targetPath);
      if (!exported.contains(name)) continue;

      // Now find the declaration — either in targetPath itself or
      // transitively through its exports.
      final loc = _findDeclarationInExports(name, targetPath, <String>{});
      if (loc != null) return loc;
    }

    return null;
  }

  SymbolLocation? _findDeclarationInExports(
    String name,
    String path,
    Set<String> visited,
  ) {
    if (visited.contains(path)) return null;
    visited.add(path);
    final file = files[path];
    if (file == null) return null;

    final ownDecl = file.symbols.findDeclaration(name);
    if (ownDecl != null) {
      return SymbolLocation(
        filePath: path,
        name: name,
        declarationNameSpan: ownDecl.nameSpan,
        declarationSpan: ownDecl.declarationSpan,
        kind: ownDecl.kind,
      );
    }

    for (final exp in file.directives.exports) {
      if (!_namePassesCombinators(name, exp.combinators)) continue;
      final resolvedUri = resolveImportUri(exp.uri, fromFile: path)?.toString();
      if (resolvedUri == null) continue;
      final targetPath = _findFileByUriString(resolvedUri);
      if (targetPath == null) continue;
      final loc = _findDeclarationInExports(name, targetPath, visited);
      if (loc != null) return loc;
    }
    return null;
  }

  /// Locates a project file whose path equals [uriString]. Returns
  /// null if no match. Canonicalizes [uriString] so callers can pass
  /// any equivalent form of the same path.
  String? _findFileByUriString(String uriString) {
    final canonical = canonicalizeFileKey(uriString);
    if (files.containsKey(canonical)) return canonical;
    return null;
  }

  /// Filters [names] through a directive's combinators (show/hide).
  /// Multiple combinators compose: a `show A show B hide C` applied
  /// in order leaves names visible iff EACH combinator admits them.
  Set<String> _applyCombinators(
    Set<String> names,
    List<CombinatorNode> combinators,
  ) {
    var current = names;
    for (final c in combinators) {
      if (c is ShowCombinatorNode) {
        current = current.intersection(c.names.toSet());
      } else if (c is HideCombinatorNode) {
        current = current.difference(c.names.toSet());
      }
    }
    return current;
  }

  /// True iff [name] would pass every combinator's filter.
  bool _namePassesCombinators(
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

  /// Resolves an import URI string to its target URI.
  ///
  /// Resolution rules:
  ///   * `dart:foo` URIs (SDK) — returned as-is.
  ///   * `package:foo/bar.dart` URIs — looked up via [packageConfig].
  ///     Returns null when the package is not in the config.
  ///   * Relative URIs (e.g. `helper.dart`, `../utils.dart`) —
  ///     resolved against [fromFile]'s URI. [fromFile] must be a
  ///     valid URI string (the kernel's file paths SHOULD be).
  ///   * Absolute URIs (e.g. `file:///...`) — returned as-is.
  ///
  /// Returns null when resolution fails (unknown package, malformed
  /// URI). Throws nothing — failure is silent so callers can decide
  /// how to handle missing dependencies.
  Uri? resolveImportUri(String uriString, {required String fromFile}) {
    final Uri uri;
    try {
      uri = Uri.parse(uriString);
    } catch (_) {
      return null;
    }

    if (uri.scheme == 'dart') {
      // SDK URI — return as-is. No resolution to a file.
      return uri;
    }

    if (uri.scheme == 'package') {
      return packageConfig.resolvePackageUri(uri);
    }

    if (uri.hasAbsolutePath || uri.scheme.isNotEmpty) {
      // Already absolute (`/foo/bar.dart` or `file:///...`).
      return uri;
    }

    // Relative URI — resolve against fromFile. Canonicalize first so
    // raw Windows paths get a proper `file:///` scheme; otherwise
    // `Uri.parse(r'C:\foo\main.dart')` would read `C` as the scheme and
    // resolution would produce nonsense.
    final canonicalFrom = canonicalizeFileKey(fromFile);
    final Uri fromUri;
    try {
      fromUri = Uri.parse(canonicalFrom);
    } catch (_) {
      return null;
    }
    return fromUri.resolveUri(uri);
  }

  @override
  String toString() => 'ProjectModel(${files.length} file(s))';
}

/// A single file in a `ProjectModel`. Holds the path, the source
/// string, and the parsed directives.
///
/// Note: only directives are pre-parsed (M9.0b scope). Other per-file
/// models (widget tree, class structure, function body) are parsed
/// on demand by callers using the M5–M8 parsers. Top-level symbols
/// are parsed lazily via `symbols` (M9.3).
class ProjectFile {
  ProjectFile({
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

  FileSymbols? _symbols;

  /// Top-level declared names (M9.3). Lazily parsed on first access.
  FileSymbols get symbols => _symbols ??= parseFileSymbols(source);

  @override
  String toString() => 'ProjectFile($path)';
}

/// The result of `ProjectModel.resolveSymbol` — identifies a top-level
/// declaration's name and location.
class SymbolLocation {
  const SymbolLocation({
    required this.filePath,
    required this.name,
    required this.declarationNameSpan,
    required this.declarationSpan,
    required this.kind,
  });

  /// Path of the file that declares the symbol.
  final String filePath;

  /// The declared name.
  final String name;

  /// Span of the name token within the declaration file. Useful for
  /// renaming.
  final SourceSpan declarationNameSpan;

  /// Span of the full declaration.
  final SourceSpan declarationSpan;

  /// The kind of declaration (class, function, etc.).
  final DeclarationKind kind;

  @override
  String toString() => 'SymbolLocation($name @ $filePath)';
}
