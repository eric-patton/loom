import 'package:loom/loom.dart';
import 'package:test/test.dart';

void main() {
  group('JsonSerializableView.from', () {
    test('returns null for unannotated class', () {
      const source = 'class Plain { final String name; Plain(this.name); }';
      final model = parseClassStructure(source);
      expect(JsonSerializableView.from(model), isNull);
    });

    test('recognizes @JsonSerializable() class with fields', () {
      const source = '''
@JsonSerializable()
class Person {
  final String firstName;
  final String lastName;
  final int age;
  Person({required this.firstName, required this.lastName, required this.age});
}
''';
      final model = parseClassStructure(source);
      final view = JsonSerializableView.from(model);
      expect(view, isNotNull);
      expect(view!.classNode.className, equals('Person'));
      expect(view.fields.map((f) => f.name).toList(),
          equals(['firstName', 'lastName', 'age']));
      expect(view.fields[0].typeName, equals('String'));
      expect(view.fields[2].typeName, equals('int'));
    });

    test('jsonKeyName defaults to Dart name when @JsonKey is absent', () {
      const source = '''
@JsonSerializable()
class Person {
  final String firstName;
  Person(this.firstName);
}
''';
      final model = parseClassStructure(source);
      final view = JsonSerializableView.from(model)!;
      expect(view.fields.first.jsonKeyName, equals('firstName'));
      expect(view.fields.first.jsonKey, isNull);
    });

    test('jsonKeyName uses @JsonKey(name: ...) when present', () {
      const source = '''
@JsonSerializable()
class Person {
  @JsonKey(name: 'first_name')
  final String firstName;
  Person(this.firstName);
}
''';
      final model = parseClassStructure(source);
      final view = JsonSerializableView.from(model)!;
      expect(view.fields.first.jsonKeyName, equals('first_name'));
      expect(view.fields.first.jsonKey, isNotNull);
      expect(view.fields.first.jsonKey!.name, equals('JsonKey'));
    });

    test('captures fromJson constructor and toJson method', () {
      const source = '''
@JsonSerializable()
class Person {
  final String name;
  Person(this.name);

  factory Person.fromJson(Map<String, dynamic> json) =>
      _\$PersonFromJson(json);

  Map<String, dynamic> toJson() => _\$PersonToJson(this);
}
''';
      final model = parseClassStructure(source);
      final view = JsonSerializableView.from(model)!;
      expect(view.fromJsonConstructor, isNotNull);
      expect(
          view.fromJsonConstructor!.namedConstructorName, equals('fromJson'));
      expect(view.toJsonMethod, isNotNull);
      expect(view.toJsonMethod!.name, equals('toJson'));
    });

    test('excludes static fields', () {
      const source = '''
@JsonSerializable()
class Config {
  static const kVersion = 1;
  final String env;
  Config(this.env);
}
''';
      final model = parseClassStructure(source);
      final view = JsonSerializableView.from(model)!;
      expect(view.fields.map((f) => f.name).toList(), equals(['env']));
    });

    test('exposes the @JsonSerializable annotation for class-level edits', () {
      const source = '''
@JsonSerializable(fieldRename: FieldRename.snake)
class Person {
  final String firstName;
  Person(this.firstName);
}
''';
      final model = parseClassStructure(source);
      final view = JsonSerializableView.from(model)!;
      expect(view.annotation.name, equals('JsonSerializable'));
      expect(view.annotation.arguments, hasLength(1));
      final arg =
          view.annotation.arguments.first as NamedAnnotationArgumentNode;
      expect(arg.name, equals('fieldRename'));
      expect(arg.valueSource, equals('FieldRename.snake'));
    });
  });

  group('JsonSerializableView — edit interop', () {
    test('removeMember on a field also removes its JsonKey annotation', () {
      const source = '''
@JsonSerializable()
class Person {
  @JsonKey(name: 'first_name')
  final String firstName;
  final String lastName;
}
''';
      final model = parseClassStructure(source);
      final view = JsonSerializableView.from(model)!;
      final firstName = view.fields.first;
      final edit = ClassStructureEditPlanner.removeMember(
        member: firstName.field,
        source: source,
      );
      final out = applySourceEdits(source, [edit]);
      // Field declaration AND its @JsonKey annotation both gone.
      expect(out, isNot(contains('firstName')));
      expect(out, isNot(contains('JsonKey')));
      expect(out, contains('final String lastName'));
    });

    test('changing JsonKey name argument propagates to jsonKeyName', () {
      const source = '''
@JsonSerializable()
class Person {
  @JsonKey(name: 'first_name')
  final String firstName;
  Person(this.firstName);
}
''';
      final model = parseClassStructure(source);
      final view = JsonSerializableView.from(model)!;
      final field = view.fields.first;
      final jsonKey = field.jsonKey!;
      final nameArg = jsonKey.arguments.first as NamedAnnotationArgumentNode;
      final edit = AnnotationEditPlanner.changeAnnotationArgumentValue(
        argument: nameArg,
        newValueSource: "'firstName'",
      );
      final out = applySourceEdits(source, [edit]);
      expect(out, contains("@JsonKey(name: 'firstName')"));
    });
  });
}
