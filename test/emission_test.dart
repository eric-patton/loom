import 'package:loom/loom.dart';
import 'package:test/test.dart';

const _span = SourceSpan(offset: 0, length: 0);

void main() {
  group('PropertySerializer', () {
    test('string literal - basic', () {
      const v = StringLiteralValue(value: 'hello', span: _span);
      expect(PropertySerializer.serialize(v), equals("'hello'"));
    });

    test('string literal - escapes single quote', () {
      const v = StringLiteralValue(value: "it's", span: _span);
      expect(PropertySerializer.serialize(v), equals(r"'it\'s'"));
    });

    test('string literal - escapes backslash', () {
      const v = StringLiteralValue(value: r'a\b', span: _span);
      expect(PropertySerializer.serialize(v), equals(r"'a\\b'"));
    });

    test('integer literal', () {
      const v = NumLiteralValue(value: 42, isDouble: false, span: _span);
      expect(PropertySerializer.serialize(v), equals('42'));
    });

    test('double literal - non-integer value', () {
      const v = NumLiteralValue(value: 3.14, isDouble: true, span: _span);
      expect(PropertySerializer.serialize(v), equals('3.14'));
    });

    test('double literal - integer-shaped value forces decimal point', () {
      // value=8 (int) with isDouble=true must still emit 8.0
      const v = NumLiteralValue(value: 8, isDouble: true, span: _span);
      expect(PropertySerializer.serialize(v), equals('8.0'));
    });

    test('bool literal - true', () {
      const v = BoolLiteralValue(value: true, span: _span);
      expect(PropertySerializer.serialize(v), equals('true'));
    });

    test('bool literal - false', () {
      const v = BoolLiteralValue(value: false, span: _span);
      expect(PropertySerializer.serialize(v), equals('false'));
    });

    test('null literal', () {
      const v = NullLiteralValue(span: _span);
      expect(PropertySerializer.serialize(v), equals('null'));
    });

    test('EdgeInsets.all with double', () {
      const v = EdgeInsetsAllValue(
        amount: 8,
        amountIsDouble: true,
        span: _span,
      );
      expect(PropertySerializer.serialize(v), equals('EdgeInsets.all(8.0)'));
    });

    test('EdgeInsets.all with int', () {
      const v = EdgeInsetsAllValue(
        amount: 16,
        amountIsDouble: false,
        span: _span,
      );
      expect(PropertySerializer.serialize(v), equals('EdgeInsets.all(16)'));
    });

    test('Color literal', () {
      const v = ColorValue(argbValue: 0xFF112233, span: _span);
      expect(PropertySerializer.serialize(v), equals('Color(0xFF112233)'));
    });

    test('Color literal pads to 8 hex digits', () {
      const v = ColorValue(argbValue: 0x000000FF, span: _span);
      expect(PropertySerializer.serialize(v), equals('Color(0x000000FF)'));
    });

    test('enum reference', () {
      const v = EnumReferenceValue(
        typeName: 'MainAxisAlignment',
        memberName: 'center',
        span: _span,
      );
      expect(
          PropertySerializer.serialize(v), equals('MainAxisAlignment.center'));
    });
  });

  group('EditPlanner.propertyEdit', () {
    test('emits a SourceEdit covering the old value range', () {
      const oldValue = StringLiteralValue(
        value: 'hello',
        span: SourceSpan(offset: 100, length: 7), // 'hello' incl quotes
      );
      const newValue = StringLiteralValue(value: 'world', span: _span);

      final edit = EditPlanner.propertyEdit(
        oldValue: oldValue,
        newValue: newValue,
      );

      expect(edit.offset, equals(100));
      expect(edit.length, equals(7));
      expect(edit.replacement, equals("'world'"));
    });

    test('apply yields the expected source string', () {
      const source = "Text('hello')";
      // 'hello' is at offset 5, length 7 (with quotes)
      const oldValue = StringLiteralValue(
        value: 'hello',
        span: SourceSpan(offset: 5, length: 7),
      );
      const newValue = StringLiteralValue(value: 'world', span: _span);

      final edit = EditPlanner.propertyEdit(
        oldValue: oldValue,
        newValue: newValue,
      );
      final result = applySourceEdits(source, [edit]);

      expect(result, equals("Text('world')"));
    });

    test('end-to-end: parse, edit, apply, re-parse picks up the new value', () {
      const source = '''
class App extends StatelessWidget {
  Widget build(BuildContext context) {
    return const Text('hello');
  }
}
''';
      final model = parseWidgetTree(source);
      final oldValue = model.root.properties['data']! as StringLiteralValue;
      const newValue = StringLiteralValue(value: 'world', span: _span);

      final edit = EditPlanner.propertyEdit(
        oldValue: oldValue,
        newValue: newValue,
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseWidgetTree(newSource);
      final reparsedData =
          reparsed.root.properties['data']! as StringLiteralValue;
      expect(reparsedData.value, equals('world'));

      // Minimal-diff invariant: substituting 'world' back to 'hello'
      // recovers the original source byte-for-byte.
      expect(newSource.replaceAll("'world'", "'hello'"), equals(source));
    });
  });
}
