/// Class-structure round-trip tests (M7.0). Validates the same invariants
/// from PROJECT_SPEC for the fourth model kind (class structure).
library;

import 'dart:io';

import 'package:loom/loom.dart';
import 'package:test/test.dart';

String _loadFixture(String name) =>
    File('test/fixtures/$name').readAsStringSync();

void main() {
  group('invariant 2 - no-op idempotence (class structure)', () {
    for (final fixture in ['class_simple.dart', 'class_with_methods.dart']) {
      test('apply([], source) == source on $fixture', () {
        final source = _loadFixture(fixture);
        final model = parseClassStructure(source);
        final result = applySourceEdits(source, const <SourceEdit>[]);
        expect(result, equals(source));
        expect(model.root.className, isNotEmpty);
      });
    }
  });

  group('renameField', () {
    test('renames "name" -> "fullName" preserves outside bytes', () {
      final source = _loadFixture('class_simple.dart');
      final model = parseClassStructure(source);
      final nameField = model.root.fields.firstWhere((f) => f.name == 'name');

      final edit = ClassStructureEditPlanner.renameField(
        field: nameField,
        newName: 'fullName',
      );
      final newSource = applySourceEdits(source, [edit]);

      // Prefix and suffix unchanged.
      expect(
        newSource.substring(0, nameField.nameSpan.offset),
        equals(source.substring(0, nameField.nameSpan.offset)),
      );
      expect(
        newSource.substring(
          nameField.nameSpan.offset + edit.replacement.length,
        ),
        equals(source.substring(nameField.nameSpan.end)),
      );

      // Re-parse: field name is updated.
      final reparsed = parseClassStructure(newSource);
      final names = reparsed.root.fields.map((f) => f.name).toList();
      expect(names, contains('fullName'));
      expect(names, isNot(contains('name')));
    });
  });

  group('changeFieldType', () {
    test('changes age type "int" -> "BigInt"', () {
      final source = _loadFixture('class_simple.dart');
      final model = parseClassStructure(source);
      final ageField = model.root.fields.firstWhere((f) => f.name == 'age');

      final edit = ClassStructureEditPlanner.changeFieldType(
        field: ageField,
        newType: 'BigInt',
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseClassStructure(newSource);
      final age = reparsed.root.fields.firstWhere((f) => f.name == 'age');
      expect(age.typeName, equals('BigInt'));
    });
  });

  group('changeFieldInitializer', () {
    test('changes age initializer "0" -> "42"', () {
      final source = _loadFixture('class_with_methods.dart');
      final model = parseClassStructure(source);
      final ageField = model.root.fields.firstWhere((f) => f.name == 'age');
      expect(ageField.initializerSource, equals('0'));

      final edit = ClassStructureEditPlanner.changeFieldInitializer(
        field: ageField,
        newInitializerSource: '42',
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseClassStructure(newSource);
      final age = reparsed.root.fields.firstWhere((f) => f.name == 'age');
      expect(age.initializerSource, equals('42'));
    });
  });

  group('removeField', () {
    test('removes "email" field cleanly', () {
      final source = _loadFixture('class_simple.dart');
      final model = parseClassStructure(source);
      final email = model.root.fields.firstWhere((f) => f.name == 'email');

      final edit = ClassStructureEditPlanner.removeField(
        field: email,
        source: source,
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseClassStructure(newSource);
      final names = reparsed.root.fields.map((f) => f.name).toList();
      expect(names, isNot(contains('email')));
      expect(reparsed.root.fields, hasLength(3));
    });
  });

  group('addField', () {
    test('appends new field to a class with existing fields', () {
      final source = _loadFixture('class_simple.dart');
      final model = parseClassStructure(source);

      final edit = ClassStructureEditPlanner.addField(
        parent: model.root,
        newFieldSource: 'String? phoneNumber;',
        source: source,
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseClassStructure(newSource);
      final names = reparsed.root.fields.map((f) => f.name).toList();
      expect(names, contains('phoneNumber'));
      expect(reparsed.root.fields, hasLength(5));

      // Newly-added field should be the last one.
      expect(reparsed.root.fields.last.name, equals('phoneNumber'));
      expect(reparsed.root.fields.last.typeName, equals('String?'));
    });

    test('appends field to a class with methods (after the methods)', () {
      final source = _loadFixture('class_with_methods.dart');
      final model = parseClassStructure(source);

      final edit = ClassStructureEditPlanner.addField(
        parent: model.root,
        newFieldSource: 'String? nickname;',
        source: source,
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseClassStructure(newSource);
      final names = reparsed.root.fields.map((f) => f.name).toList();
      expect(names, contains('nickname'));
    });
  });
}
