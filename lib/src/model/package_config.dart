/// A mapping of package names to their root URIs (the directory that
/// contains each package's `lib/`). Used by `ProjectModel` to resolve
/// `package:` import URIs to concrete file URIs.
///
/// **Pure Dart, no I/O.** The kernel doesn't read `package_config.json`
/// directly — that's caller territory (and varies by build environment).
/// Pass a `PackageConfig` constructed however suits your use case:
///   * Build it from a `package_config.json` file via `dart:io` /
///     `dart:convert` in a CLI.
///   * Build it from a Map in a test.
///   * Build it from a Bazel/Buck build graph.
///
/// The kernel only implements the URI resolution algorithm.
class PackageConfig {
  /// Constructs a config from a map of package name → root URI.
  ///
  /// Each root URI should end with a trailing slash. For example:
  /// `{'foo': Uri.parse('file:///pkg/foo/lib/')}`.
  PackageConfig({required Map<String, Uri> packageRootUris})
      : packageRootUris = Map.unmodifiable(packageRootUris);

  /// An empty config — no packages registered. `resolvePackageUri`
  /// always returns null for `package:` URIs.
  PackageConfig.empty() : packageRootUris = const {};

  /// Read-only map of package name → root URI.
  final Map<String, Uri> packageRootUris;

  /// Resolves a `package:foo/path.dart` URI to its concrete URI by
  /// looking up `foo` in the config. Returns null if `foo` is not
  /// in the config.
  ///
  /// Throws `ArgumentError` if [packageUri] is not a `package:` URI.
  Uri? resolvePackageUri(Uri packageUri) {
    if (packageUri.scheme != 'package') {
      throw ArgumentError(
        'resolvePackageUri requires a package: URI; got $packageUri.',
      );
    }
    // package:foo/bar/baz.dart → first path segment is the package
    // name; the rest is the path relative to the package's lib root.
    if (packageUri.pathSegments.isEmpty) return null;
    final packageName = packageUri.pathSegments.first;
    final root = packageRootUris[packageName];
    if (root == null) return null;
    final relativePath = packageUri.pathSegments.skip(1).join('/');
    return root.resolve(relativePath);
  }

  @override
  String toString() => 'PackageConfig(${packageRootUris.length} package(s))';
}
