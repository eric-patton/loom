import 'package:loom/loom.dart';
import 'package:test/test.dart';

void main() {
  group('parseFileSymbols', () {
    test('captures top-level declarations of all common kinds', () {
      const source = '''
class Foo {}
class Bar extends Foo {}
mixin M {}
enum E { a, b }
typedef IntCallback = void Function(int);
extension StringX on String {}
const x = 1;
final y = 2;
int z = 3;
void f() {}
''';
      final symbols = parseFileSymbols(source);
      expect(
        symbols.names,
        containsAll([
          'Foo',
          'Bar',
          'M',
          'E',
          'IntCallback',
          'StringX',
          'x',
          'y',
          'z',
          'f',
        ]),
      );
    });

    test('unnamed extension declares no name', () {
      const source = 'extension on String { String trim2() => trim(); }';
      final symbols = parseFileSymbols(source);
      expect(symbols.names, isEmpty);
    });

    test('multi-var top-level decl produces multiple symbols', () {
      const source = 'var a = 1, b = 2, c = 3;';
      final symbols = parseFileSymbols(source);
      expect(symbols.names, equals({'a', 'b', 'c'}));
    });
  });

  group('parseFileSymbols — top-level annotations (M10.0a)', () {
    test('captures annotations on a class declaration', () {
      const source = "@JsonSerializable()\nclass Person {}\n";
      final symbols = parseFileSymbols(source);
      final person = symbols.findDeclaration('Person');
      expect(person, isNotNull);
      expect(person!.annotations, hasLength(1));
      expect(person.annotations.first.name, equals('JsonSerializable'));
      expect(
        person.annotations.first.argumentsSource,
        equals('()'),
      );
    });

    test('captures bare annotation (no parens)', () {
      const source = "@freezed\nclass Person {}\n";
      final symbols = parseFileSymbols(source);
      final person = symbols.findDeclaration('Person')!;
      expect(person.annotations, hasLength(1));
      expect(person.annotations.first.name, equals('freezed'));
      expect(person.annotations.first.argumentsSource, isNull);
    });

    test('captures multiple annotations on one declaration', () {
      const source = '''
@freezed
@JsonSerializable()
class Person {}
''';
      final symbols = parseFileSymbols(source);
      final person = symbols.findDeclaration('Person')!;
      expect(person.annotations, hasLength(2));
      expect(person.annotations[0].name, equals('freezed'));
      expect(person.annotations[1].name, equals('JsonSerializable'));
    });

    test('captures annotations on top-level function', () {
      const source = "@pragma('vm:entry-point')\nvoid main() {}\n";
      final symbols = parseFileSymbols(source);
      final main = symbols.findDeclaration('main')!;
      expect(main.annotations, hasLength(1));
      expect(main.annotations.first.name, equals('pragma'));
    });

    test('captures annotations on typedef', () {
      const source = "@deprecated\ntypedef IntCallback = void Function(int);\n";
      final symbols = parseFileSymbols(source);
      final cb = symbols.findDeclaration('IntCallback')!;
      expect(cb.annotations, hasLength(1));
      expect(cb.annotations.first.name, equals('deprecated'));
    });

    test('captures annotations on top-level variable', () {
      const source = "@deprecated\nconst kPi = 3.14;\n";
      final symbols = parseFileSymbols(source);
      final kPi = symbols.findDeclaration('kPi')!;
      expect(kPi.annotations, hasLength(1));
      expect(kPi.annotations.first.name, equals('deprecated'));
    });

    test('multi-var declaration: every variable inherits the annotations', () {
      const source = "@deprecated\nvar a = 1, b = 2;\n";
      final symbols = parseFileSymbols(source);
      expect(symbols.findDeclaration('a')!.annotations, hasLength(1));
      expect(symbols.findDeclaration('b')!.annotations, hasLength(1));
    });

    test('no annotations → empty list', () {
      const source = "class Plain {}\n";
      final symbols = parseFileSymbols(source);
      expect(symbols.findDeclaration('Plain')!.annotations, isEmpty);
    });
  });

  group('AnnotationArgumentNode — argument internals (M10.0b)', () {
    test('positional argument captures value source', () {
      const source = "@pragma('vm:entry-point')\nvoid main() {}\n";
      final symbols = parseFileSymbols(source);
      final args = symbols.findDeclaration('main')!.annotations.first.arguments;
      expect(args, hasLength(1));
      expect(args.first, isA<PositionalAnnotationArgumentNode>());
      expect(args.first.valueSource, equals("'vm:entry-point'"));
    });

    test('named argument captures name and value', () {
      const source = "@JsonKey(name: 'foo', defaultValue: 0)\nclass X {}\n";
      final symbols = parseFileSymbols(source);
      final args = symbols.findDeclaration('X')!.annotations.first.arguments;
      expect(args, hasLength(2));
      expect(args[0], isA<NamedAnnotationArgumentNode>());
      final nameArg = args[0] as NamedAnnotationArgumentNode;
      expect(nameArg.name, equals('name'));
      expect(nameArg.valueSource, equals("'foo'"));
      final defaultArg = args[1] as NamedAnnotationArgumentNode;
      expect(defaultArg.name, equals('defaultValue'));
      expect(defaultArg.valueSource, equals('0'));
    });

    test('empty parens → empty arguments list', () {
      const source = "@JsonSerializable()\nclass X {}\n";
      final symbols = parseFileSymbols(source);
      final ann = symbols.findDeclaration('X')!.annotations.first;
      expect(ann.argumentsSource, equals('()'));
      expect(ann.arguments, isEmpty);
    });

    test('mixed positional + named arguments', () {
      const source = "@Tag('foo', priority: 1)\nclass X {}\n";
      final symbols = parseFileSymbols(source);
      final args = symbols.findDeclaration('X')!.annotations.first.arguments;
      expect(args, hasLength(2));
      expect(args[0], isA<PositionalAnnotationArgumentNode>());
      expect(args[1], isA<NamedAnnotationArgumentNode>());
    });
  });

  group('ProjectModel.resolveSymbol — within a single file', () {
    test('finds a class declared in the current file', () {
      final project = ProjectModel.fromSources({
        'lib/main.dart': '''
class Foo {}
void main() {
  Foo();
}
''',
      });
      final loc = project.resolveSymbol(
        'Foo',
        fromFile: 'lib/main.dart',
      );
      expect(loc, isNotNull);
      expect(loc!.filePath, equals('lib/main.dart'));
      expect(loc.kind, equals(DeclarationKind.classKind));
    });

    test('returns null for unknown name', () {
      final project = ProjectModel.fromSources({
        'a.dart': 'class Foo {}',
      });
      expect(project.resolveSymbol('Missing', fromFile: 'a.dart'), isNull);
    });
  });

  group('ProjectModel.resolveSymbol — across imports', () {
    test('finds a class imported from another file', () {
      final project = ProjectModel.fromSources({
        'lib/main.dart': '''
import 'helper.dart';
void main() {
  hello();
}
''',
        'lib/helper.dart': '''
String hello() => 'hi';
class Util {}
''',
      });
      final loc = project.resolveSymbol('hello', fromFile: 'lib/main.dart');
      expect(loc, isNotNull);
      expect(loc!.filePath, equals('lib/helper.dart'));
    });

    test('respects show combinator', () {
      final project = ProjectModel.fromSources({
        'lib/main.dart': '''
import 'helper.dart' show foo;
''',
        'lib/helper.dart': '''
class foo {}
class bar {}
''',
      });
      expect(
        project.resolveSymbol('foo', fromFile: 'lib/main.dart')?.filePath,
        equals('lib/helper.dart'),
      );
      // `bar` is hidden by the show clause.
      expect(
        project.resolveSymbol('bar', fromFile: 'lib/main.dart'),
        isNull,
      );
    });

    test('respects hide combinator', () {
      final project = ProjectModel.fromSources({
        'lib/main.dart': '''
import 'helper.dart' hide hidden;
''',
        'lib/helper.dart': '''
class visible {}
class hidden {}
''',
      });
      expect(
        project.resolveSymbol('visible', fromFile: 'lib/main.dart')?.filePath,
        equals('lib/helper.dart'),
      );
      expect(
        project.resolveSymbol('hidden', fromFile: 'lib/main.dart'),
        isNull,
      );
    });

    test('imports under a prefix do NOT expose unprefixed names', () {
      final project = ProjectModel.fromSources({
        'lib/main.dart': '''
import 'helper.dart' as h;
''',
        'lib/helper.dart': '''
class foo {}
''',
      });
      // `foo` is only visible as `h.foo`, not as bare `foo`.
      expect(
        project.resolveSymbol('foo', fromFile: 'lib/main.dart'),
        isNull,
      );
    });
  });

  group('ProjectModel.exportedNamesOf', () {
    test('includes direct declarations + re-exports', () {
      final project = ProjectModel.fromSources({
        'lib/api.dart': '''
export 'src/util.dart';
class Public {}
''',
        'lib/src/util.dart': '''
class Util {}
class Internal {}
''',
      });
      // Note: lib/api.dart's `export 'src/util.dart'` resolves
      // relative to lib/api.dart → lib/src/util.dart.
      final exported = project.exportedNamesOf('lib/api.dart');
      expect(exported, containsAll(['Public', 'Util', 'Internal']));
    });

    test('respects export show combinator', () {
      final project = ProjectModel.fromSources({
        'lib/api.dart': "export 'src/util.dart' show Util;\n",
        'lib/src/util.dart': 'class Util {}\nclass Internal {}\n',
      });
      final exported = project.exportedNamesOf('lib/api.dart');
      expect(exported, contains('Util'));
      expect(exported, isNot(contains('Internal')));
    });

    test('cycle-safe: A exports B and B exports A', () {
      final project = ProjectModel.fromSources({
        'a.dart': "export 'b.dart';\nclass A {}\n",
        'b.dart': "export 'a.dart';\nclass B {}\n",
      });
      // Should terminate.
      final aExports = project.exportedNamesOf('a.dart');
      expect(aExports, containsAll(['A', 'B']));
    });
  });

  group('ProjectModel.resolveSymbol — through re-exports', () {
    test('follows export chain to the original declaration', () {
      final project = ProjectModel.fromSources({
        'lib/main.dart': "import 'api.dart';\n",
        'lib/api.dart': "export 'src/util.dart';\n",
        'lib/src/util.dart': 'class Util {}\n',
      });
      final loc = project.resolveSymbol('Util', fromFile: 'lib/main.dart');
      expect(loc, isNotNull);
      // The ORIGINAL declaration site is src/util.dart, not api.dart.
      expect(loc!.filePath, equals('lib/src/util.dart'));
    });
  });
}
