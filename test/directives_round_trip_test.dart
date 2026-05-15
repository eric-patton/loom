/// Directives round-trip tests (M9.0a).
library;

import 'dart:io';

import 'package:loom/loom.dart';
import 'package:test/test.dart';

String _loadFixture(String name) =>
    File('test/fixtures/$name').readAsStringSync();

void main() {
  group('invariant 2 — no-op idempotence (directives)', () {
    test('apply([], source) == source on directives_simple.dart', () {
      final source = _loadFixture('directives_simple.dart');
      expect(applySourceEdits(source, const <SourceEdit>[]), equals(source));
    });
  });

  group('addImport', () {
    test('appends after the last existing import', () {
      final source = _loadFixture('directives_simple.dart');
      final unit = parseDirectives(source);

      final edit = DirectivesEditPlanner.addImport(
        unit: unit,
        newImportSource: "import 'package:new/new.dart';",
        source: source,
      );
      final newSource = applySourceEdits(source, [edit]);

      // The new import should appear after the deferred import line.
      expect(
        newSource,
        contains("import 'package:lib/deferred.dart' deferred as d;\n"
            "import 'package:new/new.dart';"),
      );
    });

    test('inserts at top of file with no library and no existing imports', () {
      const source = '''
void main() {}
''';
      final unit = parseDirectives(source);
      final edit = DirectivesEditPlanner.addImport(
        unit: unit,
        newImportSource: "import 'dart:io';",
        source: source,
      );
      final newSource = applySourceEdits(source, [edit]);
      expect(newSource, startsWith("import 'dart:io';\n"));
    });

    test('inserts after the library directive when no imports exist', () {
      const source = '''
library foo;
void main() {}
''';
      final unit = parseDirectives(source);
      final edit = DirectivesEditPlanner.addImport(
        unit: unit,
        newImportSource: "import 'dart:io';",
        source: source,
      );
      final newSource = applySourceEdits(source, [edit]);
      expect(
        newSource,
        contains("library foo;\n\nimport 'dart:io';"),
      );
    });
  });

  group('removeDirective', () {
    test('removes an import + trailing newline', () {
      final source = _loadFixture('directives_simple.dart');
      final unit = parseDirectives(source);
      // Remove the third import (`package:foo/bar.dart show foo, bar`).
      final imports = unit.imports.toList();

      final edit = DirectivesEditPlanner.removeDirective(
        directive: imports[2],
        source: source,
      );
      final newSource = applySourceEdits(source, [edit]);
      expect(newSource, isNot(contains('package:foo/bar.dart')));
    });
  });

  group('changeDirectiveUri', () {
    test('renames an import URI', () {
      final source = _loadFixture('directives_simple.dart');
      final unit = parseDirectives(source);
      final imports = unit.imports.toList();

      final edit = DirectivesEditPlanner.changeDirectiveUri(
        directive: imports[2],
        newUri: 'package:newfoo/newbar.dart',
      );
      final newSource = applySourceEdits(source, [edit]);
      expect(newSource, contains("'package:newfoo/newbar.dart'"));
      expect(newSource, isNot(contains("'package:foo/bar.dart'")));
    });

    test('preserves quote style', () {
      const source = '''
import "package:double/quoted.dart";
void main() {}
''';
      final unit = parseDirectives(source);
      final edit = DirectivesEditPlanner.changeDirectiveUri(
        directive: unit.directives.first,
        newUri: 'package:new/new.dart',
      );
      final newSource = applySourceEdits(source, [edit]);
      // Double-quote style preserved.
      expect(newSource, contains('"package:new/new.dart"'));
    });

    test('throws on a library directive (no URI)', () {
      final source = _loadFixture('directives_simple.dart');
      final unit = parseDirectives(source);
      final lib = unit.directives.first as LibraryDirectiveNode;
      expect(
        () => DirectivesEditPlanner.changeDirectiveUri(
          directive: lib,
          newUri: 'foo',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('changeImportPrefix', () {
    test('renames `as io` to `as fs`', () {
      final source = _loadFixture('directives_simple.dart');
      final unit = parseDirectives(source);
      final imports = unit.imports.toList();
      // imports[1] is `import 'dart:io' as io;`
      final edit = DirectivesEditPlanner.changeImportPrefix(
        import: imports[1],
        newPrefix: 'fs',
      );
      final newSource = applySourceEdits(source, [edit]);
      expect(newSource, contains("import 'dart:io' as fs;"));
    });

    test('throws on import without prefix', () {
      final source = _loadFixture('directives_simple.dart');
      final unit = parseDirectives(source);
      final imports = unit.imports.toList();
      expect(
        () => DirectivesEditPlanner.changeImportPrefix(
          import: imports[0], // dart:async, no prefix
          newPrefix: 'a',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('combinator name edits', () {
    test('addCombinatorName appends to show clause', () {
      final source = _loadFixture('directives_simple.dart');
      final unit = parseDirectives(source);
      final imports = unit.imports.toList();
      // imports[2] is `... show foo, bar;`
      final show = imports[2].combinators.first;

      final edit = DirectivesEditPlanner.addCombinatorName(
        combinator: show,
        index: show.names.length,
        newName: 'baz',
      );
      final newSource = applySourceEdits(source, [edit]);
      expect(newSource, contains('show foo, bar, baz'));
    });

    test('removeCombinatorName removes from middle', () {
      const source = '''
import 'package:x/y.dart' show a, b, c;
void main() {}
''';
      final unit = parseDirectives(source);
      final imp = unit.imports.first;
      final show = imp.combinators.first;

      final edit = DirectivesEditPlanner.removeCombinatorName(
        combinator: show,
        index: 1, // 'b'
        source: source,
      );
      final newSource = applySourceEdits(source, [edit]);
      expect(newSource, contains('show a, c'));
    });

    test('addImportCombinator appends a hide clause', () {
      const source = '''
import 'package:x/y.dart' show a;
void main() {}
''';
      final unit = parseDirectives(source);
      final imp = unit.imports.first;

      final edit = DirectivesEditPlanner.addImportCombinator(
        import: imp,
        newCombinatorSource: 'hide b',
      );
      final newSource = applySourceEdits(source, [edit]);
      expect(newSource, contains('show a hide b;'));
    });
  });
}
