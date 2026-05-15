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
