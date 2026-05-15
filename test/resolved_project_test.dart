import 'dart:io';

import 'package:loom/loom.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  // Resolved analysis is heavier than parseString — these tests
  // exercise it end-to-end via a temp directory.
  group('ResolvedProject — basics', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('loom_resolved_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('resolves a single self-contained library', () async {
      final libDir = Directory(p.join(tempDir.path, 'lib'))
        ..createSync(recursive: true);
      final pubspec = File(p.join(tempDir.path, 'pubspec.yaml'));
      pubspec.writeAsStringSync('''
name: example
environment:
  sdk: ^3.5.0
''');
      final file = File(p.join(libDir.path, 'foo.dart'))..writeAsStringSync('''
int answer() => 42;
class Foo {}
''');

      final project = ResolvedProject.open(includedPaths: [tempDir.path]);
      try {
        final result = await project.getResolvedUnit(file.absolute.path);
        expect(result, isNotNull);
        // Resolved unit gives access to libraryElement + typeSystem.
        expect(result!.libraryElement, isNotNull);
        expect(result.typeSystem, isNotNull);
        // The unit declarations include the function and the class.
        final declNames = result.unit.declarations
            .map((d) => d.runtimeType.toString())
            .toList();
        expect(declNames, hasLength(2));
      } finally {
        await project.dispose();
      }
    });

    test('resolution catches semantic errors (undefined name)', () async {
      final libDir = Directory(p.join(tempDir.path, 'lib'))
        ..createSync(recursive: true);
      File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: example
environment:
  sdk: ^3.5.0
''');
      final file = File(p.join(libDir.path, 'bad.dart'))..writeAsStringSync('''
void main() {
  Doesnt_Exist x = 1;
}
''');

      final project = ResolvedProject.open(includedPaths: [tempDir.path]);
      try {
        final result = await project.getResolvedUnit(file.absolute.path);
        expect(result, isNotNull);
        // Resolved-AST diagnostics include both syntactic and semantic.
        // The undefined name should produce at least one.
        expect(result!.diagnostics, isNotEmpty);
      } finally {
        await project.dispose();
      }
    });

    test('typeOfTopLevelDeclaration — function return type', () async {
      Directory(p.join(tempDir.path, 'lib')).createSync(recursive: true);
      File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: example
environment:
  sdk: ^3.5.0
''');
      final file = File(p.join(tempDir.path, 'lib', 'types.dart'))
        ..writeAsStringSync('''
int answer() => 42;
String hello() => 'hi';
List<int> nums() => [1, 2, 3];
''');

      final project = ResolvedProject.open(includedPaths: [tempDir.path]);
      try {
        expect(
          await project.typeOfTopLevelDeclaration(
            filePath: file.absolute.path,
            name: 'answer',
          ),
          equals('int'),
        );
        expect(
          await project.typeOfTopLevelDeclaration(
            filePath: file.absolute.path,
            name: 'hello',
          ),
          equals('String'),
        );
        expect(
          await project.typeOfTopLevelDeclaration(
            filePath: file.absolute.path,
            name: 'nums',
          ),
          equals('List<int>'),
        );
      } finally {
        await project.dispose();
      }
    });

    test('typeOfTopLevelDeclaration — top-level variable', () async {
      Directory(p.join(tempDir.path, 'lib')).createSync(recursive: true);
      File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: example
environment:
  sdk: ^3.5.0
''');
      final file = File(p.join(tempDir.path, 'lib', 'vars.dart'))
        ..writeAsStringSync('''
const pi = 3.14;
final greeting = 'hi';
int counter = 0;
''');

      final project = ResolvedProject.open(includedPaths: [tempDir.path]);
      try {
        expect(
          await project.typeOfTopLevelDeclaration(
              filePath: file.absolute.path, name: 'pi'),
          equals('double'),
        );
        expect(
          await project.typeOfTopLevelDeclaration(
              filePath: file.absolute.path, name: 'greeting'),
          equals('String'),
        );
        expect(
          await project.typeOfTopLevelDeclaration(
              filePath: file.absolute.path, name: 'counter'),
          equals('int'),
        );
      } finally {
        await project.dispose();
      }
    });

    test('typeOfTopLevelDeclaration — class declaration', () async {
      Directory(p.join(tempDir.path, 'lib')).createSync(recursive: true);
      File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: example
environment:
  sdk: ^3.5.0
''');
      final file = File(p.join(tempDir.path, 'lib', 'shapes.dart'))
        ..writeAsStringSync('class Circle {}\nmixin Round {}\n');

      final project = ResolvedProject.open(includedPaths: [tempDir.path]);
      try {
        expect(
          await project.typeOfTopLevelDeclaration(
              filePath: file.absolute.path, name: 'Circle'),
          equals('Circle'),
        );
        expect(
          await project.typeOfTopLevelDeclaration(
              filePath: file.absolute.path, name: 'Round'),
          equals('Round'),
        );
      } finally {
        await project.dispose();
      }
    });

    test('typeOfTopLevelDeclaration — returns null for unknown name', () async {
      Directory(p.join(tempDir.path, 'lib')).createSync(recursive: true);
      File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: example
environment:
  sdk: ^3.5.0
''');
      final file = File(p.join(tempDir.path, 'lib', 'empty.dart'))
        ..writeAsStringSync('int x = 0;');

      final project = ResolvedProject.open(includedPaths: [tempDir.path]);
      try {
        expect(
          await project.typeOfTopLevelDeclaration(
              filePath: file.absolute.path, name: 'nope'),
          isNull,
        );
      } finally {
        await project.dispose();
      }
    });

    test('typeOfExpressionAt — literal int', () async {
      Directory(p.join(tempDir.path, 'lib')).createSync(recursive: true);
      File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: example
environment:
  sdk: ^3.5.0
''');
      const source = 'final x = 42;\n';
      final file = File(p.join(tempDir.path, 'lib', 'expr.dart'))
        ..writeAsStringSync(source);

      final project = ResolvedProject.open(includedPaths: [tempDir.path]);
      try {
        // '42' starts at offset 10 in `final x = 42;`.
        final offset = source.indexOf('42');
        expect(
          await project.typeOfExpressionAt(
            filePath: file.absolute.path,
            offset: offset,
          ),
          equals('int'),
        );
      } finally {
        await project.dispose();
      }
    });

    test('typeOfExpressionAt — string concatenation expression', () async {
      Directory(p.join(tempDir.path, 'lib')).createSync(recursive: true);
      File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: example
environment:
  sdk: ^3.5.0
''');
      const source = "final g = 'hello' + 'world';\n";
      final file = File(p.join(tempDir.path, 'lib', 'concat.dart'))
        ..writeAsStringSync(source);

      final project = ResolvedProject.open(includedPaths: [tempDir.path]);
      try {
        final offset = source.indexOf("'hello'");
        expect(
          await project.typeOfExpressionAt(
            filePath: file.absolute.path,
            offset: offset,
          ),
          equals('String'),
        );
      } finally {
        await project.dispose();
      }
    });

    test('throws StateError for a path outside any included root', () async {
      // Create the project rooted at tempDir.
      Directory(p.join(tempDir.path, 'lib')).createSync(recursive: true);
      File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: example
environment:
  sdk: ^3.5.0
''');
      File(p.join(tempDir.path, 'lib', 'inside.dart'))
          .writeAsStringSync('class A {}');

      // Make a second tempdir, write a file there but don't include it.
      final otherDir =
          await Directory.systemTemp.createTemp('loom_resolved_other_');
      try {
        final outside = File(p.join(otherDir.path, 'outside.dart'))
          ..writeAsStringSync('class B {}');

        final project = ResolvedProject.open(includedPaths: [tempDir.path]);
        try {
          // `contextFor` throws StateError when path isn't in any context.
          expect(
            () => project.getResolvedUnit(outside.absolute.path),
            throwsA(isA<StateError>()),
          );
        } finally {
          await project.dispose();
        }
      } finally {
        if (otherDir.existsSync()) await otherDir.delete(recursive: true);
      }
    });
  });
}
