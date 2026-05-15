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
