import 'package:loom/loom.dart';
import 'package:test/test.dart';

/// `path`-package canonicalization is host-OS-aware. Backslash-as-separator
/// and drive-letter-as-root semantics only resolve on Windows; on POSIX
/// hosts `C:\proj\main.dart` looks like a single filename literal. Tests
/// that depend on that behavior are gated to the Windows host.
const Map<String, dynamic> _windowsOnly = <String, dynamic>{
  '!windows': Skip(
    'Backslash-separator + drive-letter semantics require a Windows host.',
  ),
};

void main() {
  group('ProjectModel construction', () {
    test('empty project has no files', () {
      final project = ProjectModel.fromSources({});
      expect(project.files, isEmpty);
      expect(project.totalImports, equals(0));
    });

    test('parses directives for each input file', () {
      final project = ProjectModel.fromSources({
        'lib/main.dart': '''
import 'package:foo/foo.dart';
import 'helper.dart';
void main() {}
''',
        'lib/helper.dart': '''
import 'package:bar/bar.dart';
String hello() => 'hi';
''',
      });
      expect(project.files, hasLength(2));
      expect(project.totalImports, equals(3));
    });

    test('indexer returns file or null', () {
      final project = ProjectModel.fromSources({
        'a.dart': 'void main() {}',
      });
      expect(project['a.dart'], isNotNull);
      expect(project['missing.dart'], isNull);
    });
  });

  group('ProjectModel import graph queries', () {
    late ProjectModel project;

    setUp(() {
      project = ProjectModel.fromSources({
        'lib/main.dart': '''
import 'helper.dart';
import 'utils.dart';
void main() {}
''',
        'lib/helper.dart': '''
import 'utils.dart';
String hello() => 'hi';
''',
        'lib/utils.dart': '''
const x = 1;
''',
        'lib/unused.dart': '''
void unused() {}
''',
      });
    });

    test('importersOf finds files that import a specific URI', () {
      // utils.dart is imported by both main.dart and helper.dart.
      final importers = project.importersOf('utils.dart');
      expect(importers, containsAll(['lib/main.dart', 'lib/helper.dart']));
      expect(importers, hasLength(2));
    });

    test('importersOf returns empty set for unimported URI', () {
      final importers = project.importersOf('nobody.dart');
      expect(importers, isEmpty);
    });

    test('importsFrom returns the file\'s import URIs', () {
      final imports = project.importsFrom('lib/main.dart');
      expect(imports, containsAll(['helper.dart', 'utils.dart']));
    });

    test('importsFrom returns empty set for unknown path', () {
      expect(project.importsFrom('nowhere.dart'), isEmpty);
    });

    test('unused file has no importers', () {
      expect(project.importersOf('unused.dart'), isEmpty);
    });
  });

  group('ProjectModel — exportedNamesOf', () {
    test('diamond re-export: name visible via either of two paths', () {
      // Regression: _exportedNamesOf shared its visited set across recursive
      // branches, so when A re-exported the same library via two intermediate
      // barrels (B and D, with different show clauses), only the first path
      // contributed names. Both branches must walk through the shared library
      // independently to apply their own combinators.
      final project = ProjectModel.fromSources({
        'a.dart': "export 'b.dart';\nexport 'd.dart';\n",
        'b.dart': "export 'c.dart' show First;\n",
        'd.dart': "export 'c.dart' show Second;\n",
        'c.dart': '''
class First {}
class Second {}
''',
      });
      final exported = project.exportedNamesOf('a.dart');
      expect(exported, contains('First'));
      expect(exported, contains('Second'));
    });
  });

  group('ProjectModel — Windows path canonicalization', () {
    // `Uri.parse(r'C:\foo\bar.dart')` succeeds but interprets `C` as a
    // one-letter URI scheme, and silently corrupts relative-import math.
    // ProjectModel canonicalizes keys at every entry point so callers can
    // pass raw Windows paths, POSIX paths, or `file:///` URIs interchangeably.
    //
    // The canonicalizer uses the host's `path` context, so true Windows-style
    // canonicalization (recognizing backslashes as separators, drive letters
    // as roots) only works when the runtime host is Windows. Tests that
    // assert that behavior run only on Windows; the cross-platform invariants
    // (file:///, package:, dart:, relative path normalization) sit outside
    // this group and run everywhere.

    test('canonicalizeFileKey: Windows absolute path → file:/// URI', () {
      final canonical = canonicalizeFileKey(r'C:\proj\lib\main.dart');
      expect(canonical, startsWith('file:///'));
      // Same path passed twice — same key.
      final canonical2 = canonicalizeFileKey(r'C:\proj\lib\main.dart');
      expect(canonical2, equals(canonical));
    }, onPlatform: _windowsOnly);

    test(
        'canonicalizeFileKey: forward and back slashes for same Windows path '
        'collapse to one canonical form', () {
      final a = canonicalizeFileKey(r'C:\proj\lib\main.dart');
      final b = canonicalizeFileKey('C:/proj/lib/main.dart');
      expect(a, equals(b));
    }, onPlatform: _windowsOnly);

    test('canonicalizeFileKey: an already-canonical file:/// URI is preserved',
        () {
      const uri = 'file:///C:/proj/main.dart';
      expect(canonicalizeFileKey(uri), equals(uri));
    });

    test('canonicalizeFileKey: package: and dart: URIs are preserved as-is',
        () {
      expect(canonicalizeFileKey('package:foo/bar.dart'),
          equals('package:foo/bar.dart'));
      expect(canonicalizeFileKey('dart:core'), equals('dart:core'));
    });

    test('canonicalizeFileKey: relative path normalized but kept relative', () {
      expect(canonicalizeFileKey('lib/main.dart'), equals('lib/main.dart'));
      // The path package folds `./` and double separators.
      expect(canonicalizeFileKey('lib/./main.dart'), equals('lib/main.dart'));
    });

    test('files map is keyed by canonical form', () {
      final project = ProjectModel.fromSources({
        r'C:\proj\main.dart': "import 'helper.dart';\nvoid main() {}\n",
        r'C:\proj\helper.dart': 'const x = 1;\n',
      });
      // Lookup by raw Windows path — should work.
      expect(project[r'C:\proj\main.dart'], isNotNull);
      // Lookup by canonical URI — should also work.
      expect(project[canonicalizeFileKey(r'C:\proj\main.dart')], isNotNull);
      // The keys stored are canonical (file:/// URIs).
      for (final key in project.files.keys) {
        expect(key, startsWith('file:///'));
      }
    }, onPlatform: _windowsOnly);

    test('cross-file import resolution works with Windows-style keys', () {
      // The bug this guards: Uri.parse(r'C:\proj\main.dart').resolveUri(
      // Uri.parse('helper.dart')) silently produces c:helper.dart because
      // backslashes aren't path separators in URI semantics. With
      // canonicalization, both the keys and the resolved URI live in the
      // same `file:///` space, so resolveImportUri actually finds helper.dart.
      final project = ProjectModel.fromSources({
        r'C:\proj\main.dart': "import 'helper.dart';\nvoid main() {}\n",
        r'C:\proj\helper.dart': 'String hi() => "hi";\n',
      });
      final resolved = project.resolveImportUri(
        'helper.dart',
        fromFile: r'C:\proj\main.dart',
      );
      expect(resolved, isNotNull);
      // The resolved URI must match the canonical key of helper.dart.
      expect(
        resolved.toString(),
        equals(canonicalizeFileKey(r'C:\proj\helper.dart')),
      );
    }, onPlatform: _windowsOnly);

    test('resolveSymbol works across files keyed by Windows-style paths', () {
      final project = ProjectModel.fromSources({
        r'C:\proj\main.dart': "import 'helper.dart';\nvoid main() {}\n",
        r'C:\proj\helper.dart': 'class Helper {}\n',
      });
      final loc = project.resolveSymbol(
        'Helper',
        fromFile: r'C:\proj\main.dart',
      );
      expect(loc, isNotNull);
      expect(
          loc!.filePath, equals(canonicalizeFileKey(r'C:\proj\helper.dart')));
      expect(loc.name, equals('Helper'));
    }, onPlatform: _windowsOnly);

    test('exportedNamesOf transitively walks barrels keyed by Windows paths',
        () {
      final project = ProjectModel.fromSources({
        r'C:\proj\barrel.dart': "export 'card.dart';\n",
        r'C:\proj\card.dart': 'class MyCard {}\n',
      });
      final names = project.exportedNamesOf(r'C:\proj\barrel.dart');
      expect(names, contains('MyCard'));
    }, onPlatform: _windowsOnly);
  });

  group('ProjectModel — parse diagnostics surface per file', () {
    test('filesWithDiagnostics flags syntactically broken files', () {
      final project = ProjectModel.fromSources({
        'good.dart': "import 'foo.dart';\nvoid main() {}\n",
        'bad.dart': 'this is not valid Dart',
      });
      final flagged = project.filesWithDiagnostics.map((f) => f.path).toSet();
      expect(flagged, contains('bad.dart'));
      expect(flagged, isNot(contains('good.dart')));
    });
  });
}
