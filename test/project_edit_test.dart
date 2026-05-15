import 'package:loom/loom.dart';
import 'package:test/test.dart';

void main() {
  group('applyProjectEdits', () {
    test('passes through files with no edits', () {
      final sources = {
        'a.dart': "import 'a.dart';",
        'b.dart': "import 'b.dart';",
      };
      final result = applyProjectEdits(sources, {});
      expect(result, equals(sources));
    });

    test('applies edits to mentioned files only', () {
      final sources = {
        'a.dart': "import 'old.dart';",
        'b.dart': "import 'other.dart';",
      };
      final project = ProjectModel.fromSources(sources);
      final edits = ProjectEditPlanner.renameImportUri(
        project: project,
        oldUri: 'old.dart',
        newUri: 'new.dart',
      );
      final result = applyProjectEdits(sources, edits);
      expect(result['a.dart'], contains("'new.dart'"));
      expect(result['b.dart'], equals(sources['b.dart']));
    });
  });

  group('addImportEverywhere', () {
    test('adds import to every file', () {
      final project = ProjectModel.fromSources({
        'a.dart': "import 'a.dart';\nvoid main() {}",
        'b.dart': 'void main() {}',
        'c.dart': "import 'package:foo/foo.dart';\nvoid main() {}",
      });
      final edits = ProjectEditPlanner.addImportEverywhere(
        project: project,
        newImportSource: "import 'package:log/log.dart';",
        uri: 'package:log/log.dart',
      );
      final result = applyProjectEdits(
        {for (final f in project.allFiles) f.path: f.source},
        edits,
      );
      for (final source in result.values) {
        expect(source, contains("import 'package:log/log.dart';"));
      }
    });

    test('skips files that already import the URI', () {
      final project = ProjectModel.fromSources({
        'a.dart': "import 'package:log/log.dart';\nvoid main() {}",
        'b.dart': 'void main() {}',
      });
      final edits = ProjectEditPlanner.addImportEverywhere(
        project: project,
        newImportSource: "import 'package:log/log.dart';",
        uri: 'package:log/log.dart',
      );
      // Only b.dart should get the import.
      expect(edits.keys, equals({'b.dart'}));
    });

    test('respects the where predicate', () {
      final project = ProjectModel.fromSources({
        'lib/a.dart': 'void main() {}',
        'lib/b.dart': 'void main() {}',
        'test/c.dart': 'void main() {}',
      });
      final edits = ProjectEditPlanner.addImportEverywhere(
        project: project,
        newImportSource: "import 'package:log/log.dart';",
        uri: 'package:log/log.dart',
        where: (f) => f.path.startsWith('lib/'),
      );
      expect(edits.keys, equals({'lib/a.dart', 'lib/b.dart'}));
    });
  });

  group('removeImportEverywhere', () {
    test('removes matching imports across all files', () {
      final project = ProjectModel.fromSources({
        'a.dart': "import 'dart:io';\nvoid main() {}",
        'b.dart': "import 'dart:io';\nimport 'dart:async';\nvoid main() {}",
        'c.dart': 'void main() {}',
      });
      final edits = ProjectEditPlanner.removeImportEverywhere(
        project: project,
        uri: 'dart:io',
      );
      final result = applyProjectEdits(
        {for (final f in project.allFiles) f.path: f.source},
        edits,
      );
      expect(result['a.dart'], isNot(contains("import 'dart:io';")));
      expect(result['b.dart'], isNot(contains("import 'dart:io';")));
      expect(result['b.dart'], contains("import 'dart:async';"));
      expect(result['c.dart'], equals('void main() {}'));
    });
  });

  group('renameImportUri', () {
    test('renames URI across all importers preserving quote style', () {
      final project = ProjectModel.fromSources({
        'a.dart': "import 'package:old/api.dart';",
        'b.dart': 'import "package:old/api.dart" as p;',
        'c.dart': "import 'package:other/x.dart';",
      });
      final edits = ProjectEditPlanner.renameImportUri(
        project: project,
        oldUri: 'package:old/api.dart',
        newUri: 'package:new/api.dart',
      );
      final result = applyProjectEdits(
        {for (final f in project.allFiles) f.path: f.source},
        edits,
      );
      // Single-quoted import preserved.
      expect(result['a.dart'], equals("import 'package:new/api.dart';"));
      // Double-quoted import preserved.
      expect(
        result['b.dart'],
        equals('import "package:new/api.dart" as p;'),
      );
      // Unrelated import untouched.
      expect(result['c.dart'], equals("import 'package:other/x.dart';"));
    });
  });

  group('M9.4 — renameTopLevelDeclaration', () {
    test('renames declaration + references in importing file', () {
      final sources = {
        'lib/api.dart': '''
class Foo {}
''',
        'lib/main.dart': '''
import 'api.dart';
void main() {
  final x = Foo();
  print(x);
}
void print(Object o) {}
''',
      };
      final project = ProjectModel.fromSources(sources);
      final loc = project.resolveSymbol('Foo', fromFile: 'lib/api.dart')!;

      final edits = ProjectEditPlanner.renameTopLevelDeclaration(
        project: project,
        symbol: loc,
        newName: 'Bar',
      );
      final result = applyProjectEdits(sources, edits);

      // Declaration renamed.
      expect(result['lib/api.dart'], contains('class Bar {}'));
      expect(result['lib/api.dart'], isNot(contains('class Foo {}')));
      // Reference in main.dart renamed.
      expect(result['lib/main.dart'], contains('Bar();'));
      expect(result['lib/main.dart'], isNot(contains('Foo();')));
    });

    test('renames internal references in the declaration file', () {
      final sources = {
        'lib/api.dart': '''
class Foo {}
Foo create() => Foo();
''',
      };
      final project = ProjectModel.fromSources(sources);
      final loc = project.resolveSymbol('Foo', fromFile: 'lib/api.dart')!;

      final edits = ProjectEditPlanner.renameTopLevelDeclaration(
        project: project,
        symbol: loc,
        newName: 'Bar',
      );
      final result = applyProjectEdits(sources, edits);

      // Both internal uses renamed.
      expect(result['lib/api.dart'], contains('class Bar {}'));
      expect(result['lib/api.dart'], contains('Bar create() => Bar();'));
      expect(result['lib/api.dart'], isNot(contains('Foo')));
    });

    test('updates show combinator referencing the renamed name', () {
      final sources = {
        'lib/api.dart': 'class Foo {}\nclass Bar {}\n',
        'lib/main.dart': "import 'api.dart' show Foo;\n",
      };
      final project = ProjectModel.fromSources(sources);
      final loc = project.resolveSymbol('Foo', fromFile: 'lib/api.dart')!;

      final edits = ProjectEditPlanner.renameTopLevelDeclaration(
        project: project,
        symbol: loc,
        newName: 'Renamed',
      );
      final result = applyProjectEdits(sources, edits);

      expect(result['lib/api.dart'], contains('class Renamed {}'));
      expect(result['lib/main.dart'], contains('show Renamed'));
    });

    test('updates hide combinator', () {
      final sources = {
        'lib/api.dart': 'class Foo {}\nclass Bar {}\n',
        'lib/main.dart': "import 'api.dart' hide Foo;\n",
      };
      final project = ProjectModel.fromSources(sources);
      final loc = project.resolveSymbol('Foo', fromFile: 'lib/api.dart')!;

      final edits = ProjectEditPlanner.renameTopLevelDeclaration(
        project: project,
        symbol: loc,
        newName: 'Renamed',
      );
      final result = applyProjectEdits(sources, edits);

      expect(result['lib/main.dart'], contains('hide Renamed'));
    });

    test('does NOT touch files that have no relationship to the symbol', () {
      final sources = {
        'lib/api.dart': 'class Foo {}\n',
        'lib/main.dart': "import 'api.dart';\nvoid main() { Foo(); }\n",
        'lib/unrelated.dart': "class Other {}\n",
      };
      final project = ProjectModel.fromSources(sources);
      final loc = project.resolveSymbol('Foo', fromFile: 'lib/api.dart')!;

      final edits = ProjectEditPlanner.renameTopLevelDeclaration(
        project: project,
        symbol: loc,
        newName: 'Bar',
      );

      // unrelated.dart is not in the edit map.
      expect(edits, isNot(contains('lib/unrelated.dart')));
    });

    test('handles re-export chain: rename propagates through api.dart', () {
      final sources = {
        'lib/src/util.dart': 'class Foo {}\n',
        'lib/api.dart': "export 'src/util.dart';\n",
        'lib/main.dart': "import 'api.dart';\nvoid main() { Foo(); }\n",
      };
      final project = ProjectModel.fromSources(sources);
      // resolveSymbol from main.dart finds Foo in src/util.dart
      // (through api.dart's re-export).
      final loc = project.resolveSymbol('Foo', fromFile: 'lib/main.dart')!;
      expect(loc.filePath, equals('lib/src/util.dart'));

      final edits = ProjectEditPlanner.renameTopLevelDeclaration(
        project: project,
        symbol: loc,
        newName: 'Bar',
      );
      final result = applyProjectEdits(sources, edits);

      expect(result['lib/src/util.dart'], contains('class Bar {}'));
      expect(result['lib/main.dart'], contains('Bar();'));
      // api.dart's export doesn't have a show clause naming Foo, so
      // it doesn't need any edits.
    });

    test('preserves string literals that happen to contain the name', () {
      final sources = {
        'lib/api.dart': 'class Foo {}\n',
        'lib/main.dart': '''
import 'api.dart';
void main() {
  final tag = 'Foo';
  Foo();
  print(tag);
}
void print(Object o) {}
''',
      };
      final project = ProjectModel.fromSources(sources);
      final loc = project.resolveSymbol('Foo', fromFile: 'lib/api.dart')!;

      final edits = ProjectEditPlanner.renameTopLevelDeclaration(
        project: project,
        symbol: loc,
        newName: 'Bar',
      );
      final result = applyProjectEdits(sources, edits);

      // The string literal 'Foo' is preserved.
      expect(result['lib/main.dart'], contains("'Foo'"));
      // But the identifier reference is renamed.
      expect(result['lib/main.dart'], contains('Bar();'));
    });
  });

  group('merge', () {
    test('combines two non-overlapping edit maps', () {
      final a = {
        'a.dart': [const SourceEdit(offset: 0, length: 0, replacement: 'A')]
      };
      final b = {
        'b.dart': [const SourceEdit(offset: 0, length: 0, replacement: 'B')]
      };
      final merged = ProjectEditPlanner.merge(a, b);
      expect(merged, hasLength(2));
      expect(merged.keys, containsAll(['a.dart', 'b.dart']));
    });

    test('concatenates per-file edit lists', () {
      final a = {
        'a.dart': [const SourceEdit(offset: 0, length: 0, replacement: 'A')]
      };
      final b = {
        'a.dart': [const SourceEdit(offset: 5, length: 0, replacement: 'B')]
      };
      final merged = ProjectEditPlanner.merge(a, b);
      expect(merged['a.dart'], hasLength(2));
    });
  });
}
