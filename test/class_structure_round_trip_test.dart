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
    for (final fixture in [
      'class_simple.dart',
      'class_with_methods.dart',
      'class_with_constructors.dart',
      'class_freezed_like.dart',
    ]) {
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

  group('renameMethod (M7.1)', () {
    test('renames isAdult -> isMinor', () {
      final source = _loadFixture('class_with_methods.dart');
      final model = parseClassStructure(source);
      final method = model.root.members.whereType<ClassMethodNode>().firstWhere(
            (m) => m.name == 'isAdult',
          );

      final edit = ClassStructureEditPlanner.renameMethod(
        method: method,
        newName: 'isMinor',
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseClassStructure(newSource);
      final names = reparsed.root.members
          .whereType<ClassMethodNode>()
          .map((m) => m.name)
          .toList();
      expect(names, contains('isMinor'));
      expect(names, isNot(contains('isAdult')));
    });
  });

  group('changeMethodReturnType (M7.1)', () {
    test('changes isAdult return type bool -> Future<bool>', () {
      final source = _loadFixture('class_with_methods.dart');
      final model = parseClassStructure(source);
      final method = model.root.members.whereType<ClassMethodNode>().firstWhere(
            (m) => m.name == 'isAdult',
          );

      final edit = ClassStructureEditPlanner.changeMethodReturnType(
        method: method,
        newReturnType: 'Future<bool>',
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseClassStructure(newSource);
      final updated = reparsed.root.members
          .whereType<ClassMethodNode>()
          .firstWhere((m) => m.name == 'isAdult');
      expect(updated.returnType, equals('Future<bool>'));
    });
  });

  group('removeMember (M7.1)', () {
    test('removes the operator+ method', () {
      final source = _loadFixture('class_with_constructors.dart');
      final model = parseClassStructure(source);
      final op = model.root.members.whereType<ClassMethodNode>().firstWhere(
            (m) => m.isOperator,
          );

      final edit = ClassStructureEditPlanner.removeMember(
        member: op,
        source: source,
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseClassStructure(newSource);
      expect(
        reparsed.root.members
            .whereType<ClassMethodNode>()
            .any((m) => m.isOperator),
        isFalse,
      );
    });

    test('removes the Money.zero constructor', () {
      final source = _loadFixture('class_with_constructors.dart');
      final model = parseClassStructure(source);
      final zero = model.root.members
          .whereType<ClassConstructorNode>()
          .firstWhere((c) => c.namedConstructorName == 'zero');

      final edit = ClassStructureEditPlanner.removeMember(
        member: zero,
        source: source,
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseClassStructure(newSource);
      final ctors = reparsed.root.members.whereType<ClassConstructorNode>();
      expect(ctors, hasLength(3));
      expect(
        ctors.map((c) => c.namedConstructorName),
        isNot(contains('zero')),
      );
    });
  });

  group('addMember (M7.1)', () {
    test('appends a new method to class_simple.dart', () {
      final source = _loadFixture('class_simple.dart');
      final model = parseClassStructure(source);

      final edit = ClassStructureEditPlanner.addMember(
        parent: model.root,
        newMemberSource: 'String greet() => \'hi, \$name\';',
        source: source,
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseClassStructure(newSource);
      final greet = reparsed.root.members
          .whereType<ClassMethodNode>()
          .firstWhere((m) => m.name == 'greet');
      expect(greet.returnType, equals('String'));
    });
  });

  group('renameParameter (M7.2)', () {
    test('renames Person ctor param age -> years', () {
      final source = _loadFixture('class_freezed_like.dart');
      final model = parseClassStructure(source);
      final ctor = model.root.members
          .whereType<ClassConstructorNode>()
          .firstWhere((c) => c.namedConstructorName == null);
      final ageParam = ctor.parameters.firstWhere((p) => p.name == 'age');

      final edit = ClassStructureEditPlanner.renameParameter(
        parameter: ageParam,
        newName: 'years',
      );
      final newSource = applySourceEdits(source, [edit]);

      // The rename should only touch the parameter NAME, not the
      // field declaration. `final int age;` stays as-is; the
      // constructor now references `this.years` which won't resolve
      // (semantically broken), but the parse should still succeed
      // syntactically and the edit-planner's job is byte-level
      // correctness, not semantic validity.
      final reparsed = parseClassStructure(newSource);
      final reparsedCtor = reparsed.root.members
          .whereType<ClassConstructorNode>()
          .firstWhere((c) => c.namedConstructorName == null);
      final names = reparsedCtor.parameters.map((p) => p.name).toList();
      expect(names, contains('years'));
      expect(names, isNot(contains('age')));
    });
  });

  group('changeParameterDefault (M7.2)', () {
    test('changes age default 0 -> 18', () {
      final source = _loadFixture('class_freezed_like.dart');
      final model = parseClassStructure(source);
      final ctor = model.root.members
          .whereType<ClassConstructorNode>()
          .firstWhere((c) => c.namedConstructorName == null);
      final age = ctor.parameters.firstWhere((p) => p.name == 'age');
      expect(age.defaultValueSource, equals('0'));

      final edit = ClassStructureEditPlanner.changeParameterDefault(
        parameter: age,
        newDefaultSource: '18',
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseClassStructure(newSource);
      final reparsedAge = reparsed.root.members
          .whereType<ClassConstructorNode>()
          .firstWhere((c) => c.namedConstructorName == null)
          .parameters
          .firstWhere((p) => p.name == 'age');
      expect(reparsedAge.defaultValueSource, equals('18'));
    });
  });

  group('changeParameterType (M7.2)', () {
    test('changes a typed parameter via class_with_methods', () {
      // class_with_methods.dart has `isAdult()` with no params, but its
      // constructor parameters have `required this.firstName` style which
      // doesn't expose a type. Use class_with_constructors.dart instead
      // — its operator+ has a typed `Money other` parameter.
      final source = _loadFixture('class_with_constructors.dart');
      final model = parseClassStructure(source);
      final op = model.root.members
          .whereType<ClassMethodNode>()
          .firstWhere((m) => m.isOperator);
      final param = op.parameters.firstWhere((p) => p.name == 'other');
      expect(param.typeName, equals('Money'));

      final edit = ClassStructureEditPlanner.changeParameterType(
        parameter: param,
        newType: 'NumericMoney',
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseClassStructure(newSource);
      final reparsedParam = reparsed.root.members
          .whereType<ClassMethodNode>()
          .firstWhere((m) => m.isOperator)
          .parameters
          .firstWhere((p) => p.name == 'other');
      expect(reparsedParam.typeName, equals('NumericMoney'));
    });
  });

  group('appendParameter (M7.2.1)', () {
    test('appends a new named parameter to Person Freezed ctor', () {
      final source = _loadFixture('class_freezed_like.dart');
      final model = parseClassStructure(source);
      final ctor = model.root.members
          .whereType<ClassConstructorNode>()
          .firstWhere((c) => c.namedConstructorName == null);

      final edit = ClassStructureEditPlanner.appendParameter(
        parent: ctor,
        newParameterSource: 'this.email = const ""',
        section: ParameterSection.named,
        source: source,
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseClassStructure(newSource);
      final reparsedCtor = reparsed.root.members
          .whereType<ClassConstructorNode>()
          .firstWhere((c) => c.namedConstructorName == null);
      final names = reparsedCtor.parameters.map((p) => p.name).toList();
      expect(names, contains('email'));
      // Existing params still present + in source order.
      expect(names, equals(['firstName', 'lastName', 'age', 'email']));
    });

    test('appends a required positional to Money operator+', () {
      final source = _loadFixture('class_with_constructors.dart');
      final model = parseClassStructure(source);
      final op = model.root.members
          .whereType<ClassMethodNode>()
          .firstWhere((m) => m.isOperator);

      final edit = ClassStructureEditPlanner.appendParameter(
        parent: op,
        newParameterSource: 'String label',
        section: ParameterSection.positionalRequired,
        source: source,
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseClassStructure(newSource);
      final reparsedOp = reparsed.root.members
          .whereType<ClassMethodNode>()
          .firstWhere((m) => m.isOperator);
      expect(reparsedOp.parameters.map((p) => p.name).toList(),
          equals(['other', 'label']));
    });

    test('appendParameter throws on getter (no parameter list)', () {
      final source = _loadFixture('class_with_methods.dart');
      final model = parseClassStructure(source);
      final getter = model.root.members
          .whereType<ClassMethodNode>()
          .firstWhere((m) => m.isGetter);

      expect(
        () => ClassStructureEditPlanner.appendParameter(
          parent: getter,
          newParameterSource: 'String x',
          section: ParameterSection.positionalRequired,
          source: source,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('appendParameter throws when section is empty (non-positional)', () {
      // class_with_constructors.dart's operator+ has no named section.
      final source = _loadFixture('class_with_constructors.dart');
      final model = parseClassStructure(source);
      final op = model.root.members
          .whereType<ClassMethodNode>()
          .firstWhere((m) => m.isOperator);

      expect(
        () => ClassStructureEditPlanner.appendParameter(
          parent: op,
          newParameterSource: 'required String x',
          section: ParameterSection.named,
          source: source,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('removeParameter (M7.2.1)', () {
    test('removes a middle named parameter', () {
      final source = _loadFixture('class_freezed_like.dart');
      final model = parseClassStructure(source);
      final ctor = model.root.members
          .whereType<ClassConstructorNode>()
          .firstWhere((c) => c.namedConstructorName == null);
      final lastName = ctor.parameters.firstWhere((p) => p.name == 'lastName');

      final edit = ClassStructureEditPlanner.removeParameter(
        parameter: lastName,
        source: source,
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseClassStructure(newSource);
      final reparsedCtor = reparsed.root.members
          .whereType<ClassConstructorNode>()
          .firstWhere((c) => c.namedConstructorName == null);
      expect(reparsedCtor.parameters.map((p) => p.name).toList(),
          equals(['firstName', 'age']));
    });

    test('removes the first named parameter', () {
      final source = _loadFixture('class_freezed_like.dart');
      final model = parseClassStructure(source);
      final ctor = model.root.members
          .whereType<ClassConstructorNode>()
          .firstWhere((c) => c.namedConstructorName == null);
      final firstName =
          ctor.parameters.firstWhere((p) => p.name == 'firstName');

      final edit = ClassStructureEditPlanner.removeParameter(
        parameter: firstName,
        source: source,
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseClassStructure(newSource);
      final reparsedCtor = reparsed.root.members
          .whereType<ClassConstructorNode>()
          .firstWhere((c) => c.namedConstructorName == null);
      expect(reparsedCtor.parameters.map((p) => p.name).toList(),
          equals(['lastName', 'age']));
    });

    test('removes the last named parameter', () {
      final source = _loadFixture('class_freezed_like.dart');
      final model = parseClassStructure(source);
      final ctor = model.root.members
          .whereType<ClassConstructorNode>()
          .firstWhere((c) => c.namedConstructorName == null);
      final age = ctor.parameters.firstWhere((p) => p.name == 'age');

      final edit = ClassStructureEditPlanner.removeParameter(
        parameter: age,
        source: source,
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseClassStructure(newSource);
      final reparsedCtor = reparsed.root.members
          .whereType<ClassConstructorNode>()
          .firstWhere((c) => c.namedConstructorName == null);
      expect(reparsedCtor.parameters.map((p) => p.name).toList(),
          equals(['firstName', 'lastName']));
    });

    test('removes the sole parameter of operator+', () {
      final source = _loadFixture('class_with_constructors.dart');
      final model = parseClassStructure(source);
      final op = model.root.members
          .whereType<ClassMethodNode>()
          .firstWhere((m) => m.isOperator);
      final other = op.parameters.single;

      final edit = ClassStructureEditPlanner.removeParameter(
        parameter: other,
        source: source,
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseClassStructure(newSource);
      final reparsedOp = reparsed.root.members
          .whereType<ClassMethodNode>()
          .firstWhere((m) => m.isOperator);
      expect(reparsedOp.parameters, isEmpty);
    });
  });

  group('annotation edits (M7.3)', () {
    test('addClassAnnotation prepends a class-level annotation', () {
      final source = _loadFixture('class_simple.dart');
      final model = parseClassStructure(source);
      // User has no annotations to start.
      expect(model.root.annotations, isEmpty);

      final edit = ClassStructureEditPlanner.addClassAnnotation(
        parent: model.root,
        annotationSource: '@JsonSerializable()',
        source: source,
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseClassStructure(newSource);
      expect(reparsed.root.annotations, hasLength(1));
      expect(reparsed.root.annotations.first.name, equals('JsonSerializable'));
      expect(
        reparsed.root.annotations.first.argumentsSource,
        equals('()'),
      );
    });

    test('addMemberAnnotation prepends an annotation before a field', () {
      final source = _loadFixture('class_simple.dart');
      final model = parseClassStructure(source);
      final name = model.root.members.whereType<ClassFieldNode>().firstWhere(
            (f) => f.name == 'name',
          );
      expect(name.annotations, isEmpty);

      final edit = ClassStructureEditPlanner.addMemberAnnotation(
        member: name,
        annotationSource: "@JsonKey(name: 'full_name')",
        source: source,
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseClassStructure(newSource);
      final updated = reparsed.root.members
          .whereType<ClassFieldNode>()
          .firstWhere((f) => f.name == 'name');
      expect(updated.annotations, hasLength(1));
      expect(updated.annotations.first.name, equals('JsonKey'));
    });

    test('addParameterAnnotation inlines an annotation before a param', () {
      final source = _loadFixture('class_freezed_like.dart');
      final model = parseClassStructure(source);
      final ctor = model.root.members
          .whereType<ClassConstructorNode>()
          .firstWhere((c) => c.namedConstructorName == null);
      final age = ctor.parameters.firstWhere((p) => p.name == 'age');
      expect(age.annotations, isEmpty);

      final edit = ClassStructureEditPlanner.addParameterAnnotation(
        parameter: age,
        annotationSource: '@Deprecated()',
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseClassStructure(newSource);
      final reparsedAge = reparsed.root.members
          .whereType<ClassConstructorNode>()
          .firstWhere((c) => c.namedConstructorName == null)
          .parameters
          .firstWhere((p) => p.name == 'age');
      expect(reparsedAge.annotations, hasLength(1));
      expect(reparsedAge.annotations.first.name, equals('Deprecated'));
    });

    test('removeAnnotation removes a member annotation cleanly', () {
      final source = _loadFixture('class_freezed_like.dart');
      final model = parseClassStructure(source);
      final firstName = model.root.members
          .whereType<ClassFieldNode>()
          .firstWhere((f) => f.name == 'firstName');
      expect(firstName.annotations, hasLength(1));

      final edit = ClassStructureEditPlanner.removeAnnotation(
        annotation: firstName.annotations.first,
        source: source,
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseClassStructure(newSource);
      final updatedFirst = reparsed.root.members
          .whereType<ClassFieldNode>()
          .firstWhere((f) => f.name == 'firstName');
      expect(updatedFirst.annotations, isEmpty);
    });

    test('removeAnnotation works on the class-level @freezed', () {
      final source = _loadFixture('class_freezed_like.dart');
      final model = parseClassStructure(source);
      expect(model.root.annotations, hasLength(1));

      final edit = ClassStructureEditPlanner.removeAnnotation(
        annotation: model.root.annotations.first,
        source: source,
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseClassStructure(newSource);
      expect(reparsed.root.annotations, isEmpty);
    });

    test('replaceAnnotationArguments updates JsonKey name', () {
      final source = _loadFixture('class_freezed_like.dart');
      final model = parseClassStructure(source);
      final firstName = model.root.members
          .whereType<ClassFieldNode>()
          .firstWhere((f) => f.name == 'firstName');
      final annotation = firstName.annotations.first;
      expect(annotation.argumentsSource, equals("(name: 'first_name')"));

      final edit = ClassStructureEditPlanner.replaceAnnotationArguments(
        annotation: annotation,
        newArgumentsSource: "(name: 'given_name', defaultValue: '')",
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseClassStructure(newSource);
      final reparsedAnnotation = reparsed.root.members
          .whereType<ClassFieldNode>()
          .firstWhere((f) => f.name == 'firstName')
          .annotations
          .first;
      expect(
        reparsedAnnotation.argumentsSource,
        equals("(name: 'given_name', defaultValue: '')"),
      );
    });

    test('replaceAnnotationArguments throws on bare annotation', () {
      final source = _loadFixture('class_freezed_like.dart');
      final model = parseClassStructure(source);
      // The class-level @freezed is bare (no args).
      final freezed = model.root.annotations.first;
      expect(freezed.argumentsSource, isNull);

      expect(
        () => ClassStructureEditPlanner.replaceAnnotationArguments(
          annotation: freezed,
          newArgumentsSource: '()',
        ),
        throwsA(isA<ArgumentError>()),
      );
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
