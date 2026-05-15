import 'package:loom/loom.dart';
import 'package:test/test.dart';

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
