import 'package:loom/loom.dart';
import 'package:test/test.dart';

AnnotationNode _firstAnnotationOn(String source, String declName) {
  final symbols = parseFileSymbols(source);
  return symbols.findDeclaration(declName)!.annotations.first;
}

void main() {
  group('AnnotationEditPlanner.addAnnotationArgument', () {
    test('inserts parens + arg into bare annotation', () {
      const source = '@deprecated\nclass X {}\n';
      final ann = _firstAnnotationOn(source, 'X');
      final edit = AnnotationEditPlanner.addAnnotationArgument(
        annotation: ann,
        newArgumentSource: "'use Y instead'",
      );
      final out = applySourceEdits(source, [edit]);
      expect(out, equals("@deprecated('use Y instead')\nclass X {}\n"));
    });

    test('inserts into empty parens', () {
      const source = '@JsonSerializable()\nclass X {}\n';
      final ann = _firstAnnotationOn(source, 'X');
      final edit = AnnotationEditPlanner.addAnnotationArgument(
        annotation: ann,
        newArgumentSource: 'fieldRename: FieldRename.snake',
      );
      final out = applySourceEdits(source, [edit]);
      expect(
          out,
          equals('@JsonSerializable(fieldRename: FieldRename.snake)\n'
              'class X {}\n'));
    });

    test('appends to non-empty parens with leading ", "', () {
      const source = "@JsonKey(name: 'foo')\nclass X {}\n";
      final ann = _firstAnnotationOn(source, 'X');
      final edit = AnnotationEditPlanner.addAnnotationArgument(
        annotation: ann,
        newArgumentSource: 'defaultValue: 0',
      );
      final out = applySourceEdits(source, [edit]);
      expect(
          out, equals("@JsonKey(name: 'foo', defaultValue: 0)\nclass X {}\n"));
    });
  });

  group('AnnotationEditPlanner.removeAnnotationArgument', () {
    test('removes the only argument, keeps parens', () {
      const source = "@JsonKey(name: 'foo')\nclass X {}\n";
      final ann = _firstAnnotationOn(source, 'X');
      final edit = AnnotationEditPlanner.removeAnnotationArgument(
        annotation: ann,
        index: 0,
        source: source,
      );
      final out = applySourceEdits(source, [edit]);
      expect(out, equals('@JsonKey()\nclass X {}\n'));
    });

    test('removes the first of two args, also drops the comma', () {
      const source = "@JsonKey(name: 'foo', defaultValue: 0)\nclass X {}\n";
      final ann = _firstAnnotationOn(source, 'X');
      final edit = AnnotationEditPlanner.removeAnnotationArgument(
        annotation: ann,
        index: 0,
        source: source,
      );
      final out = applySourceEdits(source, [edit]);
      expect(out, equals('@JsonKey(defaultValue: 0)\nclass X {}\n'));
    });

    test('removes the last of two args, also drops the leading comma', () {
      const source = "@JsonKey(name: 'foo', defaultValue: 0)\nclass X {}\n";
      final ann = _firstAnnotationOn(source, 'X');
      final edit = AnnotationEditPlanner.removeAnnotationArgument(
        annotation: ann,
        index: 1,
        source: source,
      );
      final out = applySourceEdits(source, [edit]);
      expect(out, equals("@JsonKey(name: 'foo')\nclass X {}\n"));
    });

    test('removes the middle of three args', () {
      const source = '@Foo(1, 2, 3)\nclass X {}\n';
      final ann = _firstAnnotationOn(source, 'X');
      final edit = AnnotationEditPlanner.removeAnnotationArgument(
        annotation: ann,
        index: 1,
        source: source,
      );
      final out = applySourceEdits(source, [edit]);
      expect(out, equals('@Foo(1, 3)\nclass X {}\n'));
    });

    test('throws when annotation has no arguments', () {
      const source = '@freezed\nclass X {}\n';
      final ann = _firstAnnotationOn(source, 'X');
      expect(
        () => AnnotationEditPlanner.removeAnnotationArgument(
          annotation: ann,
          index: 0,
          source: source,
        ),
        throwsArgumentError,
      );
    });

    test('throws on out-of-range index', () {
      const source = '@Foo(1)\nclass X {}\n';
      final ann = _firstAnnotationOn(source, 'X');
      expect(
        () => AnnotationEditPlanner.removeAnnotationArgument(
          annotation: ann,
          index: 5,
          source: source,
        ),
        throwsRangeError,
      );
    });
  });

  group('AnnotationEditPlanner.changeAnnotationArgumentValue', () {
    test('replaces value of a positional argument', () {
      const source = "@pragma('vm:entry-point')\nvoid main() {}\n";
      final ann = _firstAnnotationOn(source, 'main');
      final arg = ann.arguments.first;
      final edit = AnnotationEditPlanner.changeAnnotationArgumentValue(
        argument: arg,
        newValueSource: "'vm:never-inline'",
      );
      final out = applySourceEdits(source, [edit]);
      expect(out, equals("@pragma('vm:never-inline')\nvoid main() {}\n"));
    });

    test('replaces value of a named argument, keeps the name', () {
      const source = "@JsonKey(name: 'foo')\nclass X {}\n";
      final ann = _firstAnnotationOn(source, 'X');
      final arg = ann.arguments.first;
      final edit = AnnotationEditPlanner.changeAnnotationArgumentValue(
        argument: arg,
        newValueSource: "'bar'",
      );
      final out = applySourceEdits(source, [edit]);
      expect(out, equals("@JsonKey(name: 'bar')\nclass X {}\n"));
    });
  });

  group('AnnotationEditPlanner.changeAnnotationArgumentName', () {
    test('renames a named argument label', () {
      const source = "@JsonKey(name: 'foo')\nclass X {}\n";
      final ann = _firstAnnotationOn(source, 'X');
      final arg = ann.arguments.first as NamedAnnotationArgumentNode;
      final edit = AnnotationEditPlanner.changeAnnotationArgumentName(
        argument: arg,
        newName: 'jsonName',
      );
      final out = applySourceEdits(source, [edit]);
      expect(out, equals("@JsonKey(jsonName: 'foo')\nclass X {}\n"));
    });
  });

  group('round-trip — annotation argument edits', () {
    test('change-then-change leaves the rest of the source untouched', () {
      const source = '''
import 'package:json_annotation/json_annotation.dart';

@JsonSerializable()
class Person {
  @JsonKey(name: 'first_name')
  final String firstName;
  Person(this.firstName);
}
''';
      final ann = _firstAnnotationOn(source, 'Person');
      final addEdit = AnnotationEditPlanner.addAnnotationArgument(
        annotation: ann,
        newArgumentSource: 'fieldRename: FieldRename.snake',
      );
      final out = applySourceEdits(source, [addEdit]);
      // The rest of the file is preserved verbatim.
      expect(out,
          contains("import 'package:json_annotation/json_annotation.dart';"));
      expect(out, contains("@JsonKey(name: 'first_name')"));
      expect(out, contains('final String firstName;'));
      expect(
          out, contains('@JsonSerializable(fieldRename: FieldRename.snake)'));
    });
  });
}
