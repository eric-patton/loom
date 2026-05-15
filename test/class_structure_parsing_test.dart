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

    test('captures four fields, one constructor, two methods, no opaque', () {
      // M7.1: previously-opaque members are now modeled.
      // Fields: firstName, lastName, age, species (static const counts
      // as a field declaration).
      // Constructor: Person(...).
      // Methods: fullName (getter), isAdult.
      expect(root.fields, hasLength(4));
      expect(root.members.whereType<ClassConstructorNode>(), hasLength(1));
      expect(root.members.whereType<ClassMethodNode>(), hasLength(2));
      expect(root.opaqueMemberSpans, isEmpty);
    });

    test('Person constructor is captured with parameters source', () {
      final ctor = root.members.whereType<ClassConstructorNode>().single;
      expect(ctor.className, equals('Person'));
      expect(ctor.namedConstructorName, isNull);
      expect(ctor.parametersSource, startsWith('('));
      expect(ctor.parametersSource, contains('this.firstName'));
      expect(ctor.parametersSource, contains('this.lastName'));
      expect(ctor.parametersSource, contains('this.age = 0'));
      expect(ctor.isConst, isFalse);
      expect(ctor.isFactory, isFalse);
      expect(ctor.initializerListSource, isNull);
    });

    test('fullName getter is captured as ClassMethodNode with isGetter', () {
      final getter = root.members.whereType<ClassMethodNode>().firstWhere(
            (m) => m.name == 'fullName',
          );
      expect(getter.isGetter, isTrue);
      expect(getter.isSetter, isFalse);
      expect(getter.returnType, equals('String'));
      expect(getter.parametersSource, isNull); // getters have no params
      expect(getter.bodySpan, isNotNull);
    });

    test('isAdult method captured with return type + params', () {
      final method = root.members.whereType<ClassMethodNode>().firstWhere(
            (m) => m.name == 'isAdult',
          );
      expect(method.isGetter, isFalse);
      expect(method.isStatic, isFalse);
      expect(method.returnType, equals('bool'));
      expect(method.parametersSource, equals('()'));
      expect(method.bodySpan, isNotNull);
    });

    test('source order preserved in members list', () {
      final names = root.members
          .map((m) => switch (m) {
                final ClassFieldNode f => 'field:${f.name}',
                final ClassMethodNode meth => 'method:${meth.name}',
                final ClassConstructorNode c =>
                  'ctor:${c.namedConstructorName ?? c.className}',
                OpaqueClassMember() => 'opaque',
              })
          .toList();
      // Fixture order: firstName, lastName, age, Person(...), fullName,
      // isAdult, species.
      expect(
        names,
        equals([
          'field:firstName',
          'field:lastName',
          'field:age',
          'ctor:Person',
          'method:fullName',
          'method:isAdult',
          'field:species',
        ]),
      );
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

  group('parseClassStructure on class_with_constructors.dart', () {
    late ClassStructureNode root;

    setUpAll(() {
      final source =
          File('test/fixtures/class_with_constructors.dart').readAsStringSync();
      root = parseClassStructure(source).root;
    });

    test('captures all four constructors', () {
      final ctors = root.members.whereType<ClassConstructorNode>().toList();
      expect(ctors, hasLength(4));
      expect(ctors[0].namedConstructorName, isNull); // unnamed default
      expect(ctors[1].namedConstructorName, equals('zero'));
      expect(ctors[2].namedConstructorName, equals('fromString'));
      expect(ctors[3].namedConstructorName, equals('usd'));
    });

    test('const Money() is captured with isConst', () {
      final defaultCtor = root.members.whereType<ClassConstructorNode>().first;
      expect(defaultCtor.isConst, isTrue);
      expect(defaultCtor.isFactory, isFalse);
    });

    test('Money.zero captures the initializer list source', () {
      final zero = root.members.whereType<ClassConstructorNode>().firstWhere(
            (c) => c.namedConstructorName == 'zero',
          );
      expect(zero.isConst, isTrue);
      expect(zero.initializerListSource, isNotNull);
      expect(zero.initializerListSource, startsWith(':'));
      expect(zero.initializerListSource, contains('cents = 0'));
      expect(zero.initializerListSource, contains("currency = 'USD'"));
    });

    test('Money.fromString factory captured', () {
      final fromString =
          root.members.whereType<ClassConstructorNode>().firstWhere(
                (c) => c.namedConstructorName == 'fromString',
              );
      expect(fromString.isFactory, isTrue);
      expect(fromString.isConst, isFalse);
      expect(fromString.parametersSource, equals('(String input)'));
    });

    test('Money.usd redirecting factory captured', () {
      // `factory Money.usd(int cents) = Money;` — the body holds `= Money;`
      final usd = root.members.whereType<ClassConstructorNode>().firstWhere(
            (c) => c.namedConstructorName == 'usd',
          );
      expect(usd.isFactory, isTrue);
    });

    test('operator+ captured as ClassMethodNode with isOperator', () {
      final op = root.members.whereType<ClassMethodNode>().firstWhere(
            (m) => m.isOperator,
          );
      expect(op.name, equals('+'));
      expect(op.returnType, equals('Money'));
    });

    test('toString captured as a method (override is not modeled)', () {
      final toString = root.members.whereType<ClassMethodNode>().firstWhere(
            (m) => m.name == 'toString',
          );
      expect(toString.isOperator, isFalse);
      expect(toString.returnType, equals('String'));
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
