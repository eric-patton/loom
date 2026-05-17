import 'dart:io';

import 'package:loom/loom.dart';
import 'package:test/test.dart';

void main() {
  group('parseDirectives on directives_simple.dart', () {
    late String source;
    late CompilationUnitDirectives unit;

    setUpAll(() {
      source = File('test/fixtures/directives_simple.dart').readAsStringSync();
      unit = parseDirectives(source);
    });

    test('captures 9 directives in source order', () {
      // library, 5 imports, 2 exports, 1 part = 9
      expect(unit.directives, hasLength(9));
    });

    test('library directive captures name', () {
      final lib = unit.directives.first as LibraryDirectiveNode;
      expect(lib.name, equals('example.directives'));
    });

    test('imports surface as ImportDirectiveNodes with stripped URIs', () {
      final imports = unit.imports.toList();
      expect(imports, hasLength(5));
      expect(imports[0].uri, equals('dart:async'));
      expect(imports[1].uri, equals('dart:io'));
      expect(imports[1].prefix, equals('io'));
      expect(imports[2].uri, equals('package:foo/bar.dart'));
    });

    test('show combinator captures names', () {
      final imports = unit.imports.toList();
      final fooBar = imports[2];
      expect(fooBar.combinators, hasLength(1));
      final show = fooBar.combinators[0] as ShowCombinatorNode;
      expect(show.names, equals(['foo', 'bar']));
    });

    test('hide combinator captures names', () {
      final imports = unit.imports.toList();
      final barBaz = imports[3];
      final hide = barBaz.combinators[0] as HideCombinatorNode;
      expect(hide.names, equals(['quux']));
    });

    test('deferred import flag captured', () {
      final imports = unit.imports.toList();
      final deferred = imports[4];
      expect(deferred.isDeferred, isTrue);
      expect(deferred.prefix, equals('d'));
    });

    test('exports captured', () {
      final exports = unit.exports.toList();
      expect(exports, hasLength(2));
      expect(exports[0].uri, equals('src/api.dart'));
      expect(exports[1].uri, equals('src/legacy.dart'));
      expect(exports[1].combinators, hasLength(1));
    });

    test('part directive captured', () {
      final parts = unit.parts.toList();
      expect(parts, hasLength(1));
      expect(parts[0].uri, equals('helper.dart'));
    });

    test('part-of with URI form', () {
      const source = '''
part of 'main.dart';
''';
      final unit = parseDirectives(source);
      expect(unit.directives, hasLength(1));
      final p = unit.directives.first as PartOfDirectiveNode;
      expect(p.uri, equals('main.dart'));
      expect(p.libraryName, isNull);
    });

    test('part-of with dotted-name form', () {
      const source = '''
part of my.lib.name;
''';
      final unit = parseDirectives(source);
      final p = unit.directives.first as PartOfDirectiveNode;
      expect(p.libraryName, equals('my.lib.name'));
      expect(p.uri, isNull);
    });

    test('empty file produces no directives', () {
      const source = 'void main() {}\n';
      final unit = parseDirectives(source);
      expect(unit.directives, isEmpty);
      expect(unit.directiveSectionEnd, equals(0));
    });

    test('raw-string URI decodes cleanly', () {
      // Regression: _stripQuotes used to fail on raw URIs (`r'...'`)
      // because the literal starts with `r`, not a quote. The URI on
      // the model came back as `r'foo.dart'` instead of `foo.dart`.
      const source = "import r'package:foo/foo.dart';\n";
      final unit = parseDirectives(source);
      final imp = unit.directives.single as ImportDirectiveNode;
      expect(imp.uri, equals('package:foo/foo.dart'));
    });

    test('triple-quoted URI decodes cleanly', () {
      // Regression: _stripQuotes stripped only one pair of quotes,
      // leaving the inner pair. URIs end up unusable for resolution.
      const source = "import '''package:foo/foo.dart''';\n";
      final unit = parseDirectives(source);
      final imp = unit.directives.single as ImportDirectiveNode;
      expect(imp.uri, equals('package:foo/foo.dart'));
    });
  });
}
