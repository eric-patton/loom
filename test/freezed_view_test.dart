import 'package:loom/loom.dart';
import 'package:test/test.dart';

void main() {
  group('FreezedView.from', () {
    test('returns null for a plain class (no @freezed annotation)', () {
      const source = '''
class Plain {
  final String name;
  Plain(this.name);
}
''';
      final model = parseClassStructure(source);
      expect(FreezedView.from(model), isNull);
    });

    test('recognizes a singleton Freezed class with @freezed', () {
      const source = '''
@freezed
class Person with _\$Person {
  const factory Person({
    required String firstName,
    required String lastName,
    int? age,
  }) = _Person;
}
''';
      final model = parseClassStructure(source);
      final view = FreezedView.from(model);
      expect(view, isNotNull);
      expect(view!.classNode.className, equals('Person'));
      expect(view.isSingleton, isTrue);
      expect(view.variants, hasLength(1));
      final fields = view.singletonFields!;
      expect(fields.map((f) => f.name).toList(),
          equals(['firstName', 'lastName', 'age']));
      expect(fields[0].isRequired, isTrue);
      expect(fields[0].isNamed, isTrue);
      expect(fields[0].typeName, equals('String'));
      expect(fields[2].typeName, equals('int?'));
    });

    test('recognizes @Freezed(...) call-form annotation', () {
      const source = '''
@Freezed(copyWith: false)
class Settings with _\$Settings {
  const factory Settings({required String theme}) = _Settings;
}
''';
      final model = parseClassStructure(source);
      final view = FreezedView.from(model);
      expect(view, isNotNull);
      expect(view!.classNode.className, equals('Settings'));
      expect(view.singletonFields!.first.name, equals('theme'));
    });

    test('recognizes @unfreezed for mutable variants', () {
      const source = '''
@unfreezed
class MutablePerson with _\$MutablePerson {
  factory MutablePerson({required String name}) = _MutablePerson;
}
''';
      final model = parseClassStructure(source);
      final view = FreezedView.from(model);
      expect(view, isNotNull);
      expect(view!.singletonFields!.first.name, equals('name'));
    });

    test('recognizes a union (multiple factory ctors)', () {
      const source = '''
@freezed
sealed class Vehicle with _\$Vehicle {
  const factory Vehicle.car({required int wheels, required String make}) = _Car;
  const factory Vehicle.motorcycle({required int wheels}) = _Motorcycle;
}
''';
      final model = parseClassStructure(source);
      final view = FreezedView.from(model);
      expect(view, isNotNull);
      expect(view!.isSingleton, isFalse);
      expect(view.singletonFields, isNull);
      expect(view.variants, hasLength(2));
      expect(view.variants[0].variantName, equals('car'));
      expect(view.variants[1].variantName, equals('motorcycle'));
      expect(view.variants[0].fields.map((f) => f.name).toList(),
          equals(['wheels', 'make']));
      expect(view.variants[1].fields.map((f) => f.name).toList(),
          equals(['wheels']));
    });

    test('captures fromJson separately', () {
      const source = '''
@freezed
class Person with _\$Person {
  const factory Person({required String name}) = _Person;

  factory Person.fromJson(Map<String, dynamic> json) =>
      _\$PersonFromJson(json);
}
''';
      final model = parseClassStructure(source);
      final view = FreezedView.from(model)!;
      expect(view.fromJson, isNotNull);
      expect(view.fromJson!.namedConstructorName, equals('fromJson'));
      // fromJson is NOT counted as a variant.
      expect(view.variants, hasLength(1));
      expect(view.variants.first.variantName, isNull);
    });

    test('fields preserve their default values', () {
      const source = '''
@freezed
class Config with _\$Config {
  const factory Config({
    @Default(false) bool verbose,
    String? prefix,
  }) = _Config;
}
''';
      final model = parseClassStructure(source);
      final view = FreezedView.from(model)!;
      final fields = view.singletonFields!;
      expect(fields[0].name, equals('verbose'));
      expect(fields[0].defaultValueSource, isNull);
      // The @Default annotation is captured on the parameter.
      expect(fields[0].annotations, hasLength(1));
      expect(fields[0].annotations.first.name, equals('Default'));
    });
  });

  group('FreezedView — edit interop', () {
    test('appending a field via class_structure_edit_planner works', () {
      const source = '''
@freezed
class Person with _\$Person {
  const factory Person({
    required String firstName,
  }) = _Person;
}
''';
      final model = parseClassStructure(source);
      final view = FreezedView.from(model)!;
      // Add a new named-required field to the variant's constructor.
      final edit = ClassStructureEditPlanner.appendParameter(
        parent: view.variants.first.constructor,
        newParameterSource: 'required String lastName',
        section: ParameterSection.named,
        source: source,
      );
      final out = applySourceEdits(source, [edit]);
      expect(out, contains('required String firstName'));
      expect(out, contains('required String lastName'));
    });

    test('renaming a field via renameParameter works', () {
      const source = '''
@freezed
class Person with _\$Person {
  const factory Person({required String firstName}) = _Person;
}
''';
      final model = parseClassStructure(source);
      final view = FreezedView.from(model)!;
      final field = view.singletonFields!.first;
      final edit = ClassStructureEditPlanner.renameParameter(
        parameter: field.parameter,
        newName: 'first',
      );
      final out = applySourceEdits(source, [edit]);
      expect(out, contains('required String first'));
      expect(out, isNot(contains('firstName')));
    });
  });
}
