import 'package:loom/loom.dart';
import 'package:test/test.dart';

void main() {
  group('PackageConfig', () {
    test('empty config returns null for any package URI', () {
      final config = PackageConfig.empty();
      expect(
        config.resolvePackageUri(Uri.parse('package:foo/bar.dart')),
        isNull,
      );
    });

    test('resolves a known package URI', () {
      final config = PackageConfig(packageRootUris: {
        'foo': Uri.parse('file:///pkg/foo/lib/'),
      });
      final resolved =
          config.resolvePackageUri(Uri.parse('package:foo/bar.dart'));
      expect(resolved.toString(), equals('file:///pkg/foo/lib/bar.dart'));
    });

    test('resolves a nested path within a package', () {
      final config = PackageConfig(packageRootUris: {
        'foo': Uri.parse('file:///pkg/foo/lib/'),
      });
      final resolved =
          config.resolvePackageUri(Uri.parse('package:foo/nested/x.dart'));
      expect(
        resolved.toString(),
        equals('file:///pkg/foo/lib/nested/x.dart'),
      );
    });

    test('returns null for unknown package', () {
      final config = PackageConfig(packageRootUris: {
        'foo': Uri.parse('file:///pkg/foo/lib/'),
      });
      final resolved =
          config.resolvePackageUri(Uri.parse('package:bar/baz.dart'));
      expect(resolved, isNull);
    });

    test('throws on a non-package URI', () {
      final config = PackageConfig.empty();
      expect(
        () => config.resolvePackageUri(Uri.parse('dart:io')),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('ProjectModel.resolveImportUri', () {
    late ProjectModel project;

    setUp(() {
      project = ProjectModel.fromSources(
        {
          'file:///app/lib/main.dart':
              "import 'helper.dart';\nimport 'package:foo/bar.dart';\nvoid main() {}",
          'file:///app/lib/helper.dart': 'String hello() => "hi";',
        },
        packageConfig: PackageConfig(packageRootUris: {
          'foo': Uri.parse('file:///pkg/foo/lib/'),
        }),
      );
    });

    test('relative URI resolves against fromFile', () {
      final r = project.resolveImportUri(
        'helper.dart',
        fromFile: 'file:///app/lib/main.dart',
      );
      expect(r.toString(), equals('file:///app/lib/helper.dart'));
    });

    test('package URI resolves via packageConfig', () {
      final r = project.resolveImportUri(
        'package:foo/bar.dart',
        fromFile: 'file:///app/lib/main.dart',
      );
      expect(r.toString(), equals('file:///pkg/foo/lib/bar.dart'));
    });

    test('package URI with unknown package returns null', () {
      final r = project.resolveImportUri(
        'package:unknown/x.dart',
        fromFile: 'file:///app/lib/main.dart',
      );
      expect(r, isNull);
    });

    test('dart: URI returns as-is', () {
      final r = project.resolveImportUri(
        'dart:io',
        fromFile: 'file:///app/lib/main.dart',
      );
      expect(r.toString(), equals('dart:io'));
    });

    test('parent-relative URI resolves correctly', () {
      final r = project.resolveImportUri(
        '../bin/cli.dart',
        fromFile: 'file:///app/lib/main.dart',
      );
      expect(r.toString(), equals('file:///app/bin/cli.dart'));
    });

    test('default project (no config) cannot resolve package URIs', () {
      final p = ProjectModel.fromSources({'a.dart': 'void main() {}'});
      expect(
        p.resolveImportUri(
          'package:foo/bar.dart',
          fromFile: 'a.dart',
        ),
        isNull,
      );
    });

    test('relative URI from a non-URI path falls back gracefully', () {
      // When fromFile is a non-URI path, Uri.parse may still succeed
      // but resolution semantics change. Document the behavior:
      final p = ProjectModel.fromSources({
        'lib/main.dart': "import 'helper.dart';",
        'lib/helper.dart': '',
      });
      final r = p.resolveImportUri('helper.dart', fromFile: 'lib/main.dart');
      // Uri.resolveUri treats 'lib/main.dart' as relative; resolution
      // produces 'lib/helper.dart'.
      expect(r?.toString(), equals('lib/helper.dart'));
    });
  });
}
