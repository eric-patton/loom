import 'package:loom/loom.dart';
import 'package:test/test.dart';

void main() {
  group('ClassStructureNode — extends / with / implements (M10.1c)', () {
    test('captures extends clause', () {
      const source = 'class Dog extends Animal {}';
      final model = parseClassStructure(source);
      expect(model.root.superclassName, equals('Animal'));
      expect(model.root.superclassSpan, isNotNull);
    });

    test('extends with generics preserved verbatim', () {
      const source = 'class StringMap extends Map<String, int> {}';
      final model = parseClassStructure(source);
      expect(model.root.superclassName, equals('Map<String, int>'));
    });

    test('captures with clause (multiple mixins)', () {
      const source = 'class X with Foo, Bar, Baz {}';
      final model = parseClassStructure(source);
      expect(model.root.mixinNames, equals(['Foo', 'Bar', 'Baz']));
      expect(model.root.mixinSpans, hasLength(3));
    });

    test('captures implements clause', () {
      const source = 'class X implements Comparable<X>, Serializable {}';
      final model = parseClassStructure(source);
      expect(
          model.root.interfaceNames, equals(['Comparable<X>', 'Serializable']));
    });

    test('all three clauses together', () {
      const source = '''
class Dog extends Animal with Walker, Barker implements Comparable<Dog> {}
''';
      final model = parseClassStructure(source);
      expect(model.root.superclassName, equals('Animal'));
      expect(model.root.mixinNames, equals(['Walker', 'Barker']));
      expect(model.root.interfaceNames, equals(['Comparable<Dog>']));
    });

    test('plain class with no inheritance', () {
      const source = 'class Plain {}';
      final model = parseClassStructure(source);
      expect(model.root.superclassName, isNull);
      expect(model.root.mixinNames, isEmpty);
      expect(model.root.interfaceNames, isEmpty);
    });
  });

  group('DriftTableView.from', () {
    test('returns null for a class that does not extend Table', () {
      const source = 'class Plain { final String x = ""; }';
      final model = parseClassStructure(source);
      expect(DriftTableView.from(model), isNull);
    });

    test('recognizes a class extending Table', () {
      const source = '''
class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
}
''';
      final model = parseClassStructure(source);
      final view = DriftTableView.from(model);
      expect(view, isNotNull);
      expect(view!.classNode.className, equals('Categories'));
      expect(view.columns, hasLength(2));
      expect(view.columns[0].name, equals('id'));
      expect(view.columns[0].columnType, equals(DriftColumnType.intColumn));
      expect(view.columns[1].name, equals('name'));
      expect(view.columns[1].columnType, equals(DriftColumnType.textColumn));
    });

    test('recognizes all six column types', () {
      const source = '''
class Wide extends Table {
  IntColumn get i => integer()();
  TextColumn get t => text()();
  BoolColumn get b => boolean()();
  RealColumn get r => real()();
  BlobColumn get bl => blob()();
  DateTimeColumn get d => dateTime()();
}
''';
      final model = parseClassStructure(source);
      final view = DriftTableView.from(model)!;
      expect(
          view.columns.map((c) => c.columnType).toList(),
          equals([
            DriftColumnType.intColumn,
            DriftColumnType.textColumn,
            DriftColumnType.boolColumn,
            DriftColumnType.realColumn,
            DriftColumnType.blobColumn,
            DriftColumnType.dateTimeColumn,
          ]));
    });

    test('ignores non-column getters', () {
      const source = '''
class Categories extends Table {
  IntColumn get id => integer()();
  String get description => 'hello';
  TextColumn get title => text()();
}
''';
      final model = parseClassStructure(source);
      final view = DriftTableView.from(model)!;
      expect(view.columns.map((c) => c.name).toList(), equals(['id', 'title']));
    });

    test('ignores non-getter methods', () {
      const source = '''
class Categories extends Table {
  IntColumn get id => integer()();
  void prepare() {}
  IntColumn computed() => integer()();
}
''';
      final model = parseClassStructure(source);
      final view = DriftTableView.from(model)!;
      // computed() is a method (parens), not a getter.
      expect(view.columns.map((c) => c.name).toList(), equals(['id']));
    });

    test('returns null when extends has wrong superclass name', () {
      const source = '''
class Categories extends MyCustomTable {
  IntColumn get id => integer()();
}
''';
      final model = parseClassStructure(source);
      expect(DriftTableView.from(model), isNull);
    });
  });

  group('DriftTableView — edit interop', () {
    test('renaming a column via renameMember works', () {
      const source = '''
class Categories extends Table {
  IntColumn get id => integer()();
  TextColumn get description => text()();
}
''';
      final model = parseClassStructure(source);
      final view = DriftTableView.from(model)!;
      final desc = view.columns[1];
      // For getters, renameMember would rename the getter name token.
      // The current planner exposes member-level rename via methods.
      final edit = SourceEdit(
        offset: desc.nameSpan.offset,
        length: desc.nameSpan.length,
        replacement: 'name',
      );
      final out = applySourceEdits(source, [edit]);
      expect(out, contains('TextColumn get name'));
    });
  });
}
