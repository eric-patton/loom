import 'dart:io';

import 'package:loom/loom.dart';
import 'package:test/test.dart';

void main() {
  group('parseClassStructure on class_simple.dart', () {
    late ClassStructureModel model;
    late ClassStructureNode root;
    late String source;

    setUpAll(() {
      source = File('test/fixtures/class_simple.dart').readAsStringSync();
      model = parseClassStructure(source);
      root = model.root;
    });

    test('parses with no diagnostics', () {
      expect(model.diagnostics, isEmpty);
    });

    test('root class name is User', () {
      expect(root.className, equals('User'));
    });

    test('captures all four fields', () {
      expect(root.fields, hasLength(4));
    });

    test('captures opaque methods/constructors count (zero here)', () {
      expect(root.opaqueMemberSpans, isEmpty);
    });

    test('first field: final String name', () {
      final field = root.fields[0];
      expect(field.name, equals('name'));
      expect(field.typeName, equals('String'));
      expect(field.isFinal, isTrue);
      expect(field.isLate, isFalse);
      expect(field.isStatic, isFalse);
      expect(field.initializerSource, isNull);
    });

    test('second field: final int age', () {
      final field = root.fields[1];
      expect(field.name, equals('age'));
      expect(field.typeName, equals('int'));
      expect(field.isFinal, isTrue);
    });

    test('third field: nullable typed (String? email)', () {
      final field = root.fields[2];
      expect(field.name, equals('email'));
      expect(field.typeName, equals('String?'));
      expect(field.isFinal, isFalse);
    });

    test('fourth field: late final DateTime createdAt', () {
      final field = root.fields[3];
      expect(field.name, equals('createdAt'));
      expect(field.typeName, equals('DateTime'));
      expect(field.isLate, isTrue);
      expect(field.isFinal, isTrue);
    });

    test('every field name span resolves to its name in source', () {
      for (final field in root.fields) {
        expect(
          source.substring(
            field.nameSpan.offset,
            field.nameSpan.offset + field.nameSpan.length,
          ),
          equals(field.name),
        );
      }
    });

    test('class span and body span are well-formed', () {
      expect(root.classSpan.offset, equals(0));
      expect(
        source.substring(
          root.classSpan.offset,
          root.classSpan.offset + root.classSpan.length,
        ),
        startsWith('class User'),
      );
      expect(
        source.substring(
          root.bodySpan.offset,
          root.bodySpan.offset + root.bodySpan.length,
        ),
        startsWith('{'),
      );
      expect(
        source.substring(
          root.bodySpan.offset,
          root.bodySpan.offset + root.bodySpan.length,
        ),
        endsWith('}'),
      );
    });
  });

  group('parseClassStructure on class_with_methods.dart', () {
    late ClassStructureModel model;
    late ClassStructureNode root;

    setUpAll(() {
      final source =
          File('test/fixtures/class_with_methods.dart').readAsStringSync();
      model = parseClassStructure(source);
      root = model.root;
    });

    test('captures four fields and three opaque members', () {
      // Fields: firstName, lastName, age, species (static const counts as
      // a field declaration).
      // Opaque: constructor, fullName getter, isAdult method.
      expect(root.fields, hasLength(4));
      expect(root.opaqueMemberSpans, hasLength(3));
    });

    test('age field has an integer initializer captured as source', () {
      final age = root.fields.firstWhere((f) => f.name == 'age');
      expect(age.initializerSource, equals('0'));
      expect(age.typeName, equals('int'));
    });

    test('static const species captured with qualifiers', () {
      final species = root.fields.firstWhere((f) => f.name == 'species');
      expect(species.isStatic, isTrue);
      expect(species.isFinal, isFalse); // `const` field, not `final`
      expect(species.typeName, equals('String'));
      expect(species.initializerSource, equals("'Homo sapiens'"));
    });
  });

  group('parseClassStructure rejection', () {
    test('throws on a file with no class declaration', () {
      const source = 'void main() {}\n';
      expect(
        () => parseClassStructure(source),
        throwsA(isA<ParseException>()),
      );
    });
  });
}
