import 'dart:io';

import 'package:loom/loom.dart';
import 'package:test/test.dart';

const _someSpan = SourceSpan(offset: 0, length: 1);

WidgetNode _leafText(
  String data, {
  bool hasConst = false,
  SourceSpan span = _someSpan,
}) =>
    WidgetNode(
      className: 'Text',
      properties: {'data': StringLiteralValue(value: data, span: _someSpan)},
      childSlots: const {},
      sourceSpan: span,
      styleHints: StyleHints(hasConst: hasConst),
    );

void main() {
  group('StructuralEquivalence', () {
    test('a model equals itself (reflexive)', () {
      final source = File(
        'test/fixtures/simple_widget.dart',
      ).readAsStringSync();
      final model = parseWidgetTree(source);
      expect(StructuralEquivalence.equal(model, model), isTrue);
    });

    test('two re-parses of the same source produce equal models', () {
      final source = File(
        'test/fixtures/simple_widget.dart',
      ).readAsStringSync();
      final a = parseWidgetTree(source);
      final b = parseWidgetTree(source);
      expect(StructuralEquivalence.equal(a, b), isTrue);
    });

    test('different spans, otherwise identical nodes are equal', () {
      final a =
          _leafText('hello', span: const SourceSpan(offset: 0, length: 7));
      final b = _leafText(
        'hello',
        span: const SourceSpan(offset: 999, length: 99),
      );
      expect(StructuralEquivalence.nodesEqual(a, b), isTrue);
    });

    test('different className -> not equal', () {
      final a = WidgetNode(
        className: 'Text',
        properties: const {},
        childSlots: const {},
        sourceSpan: _someSpan,
        styleHints: const StyleHints(),
      );
      final b = WidgetNode(
        className: 'Tab',
        properties: const {},
        childSlots: const {},
        sourceSpan: _someSpan,
        styleHints: const StyleHints(),
      );
      expect(StructuralEquivalence.nodesEqual(a, b), isFalse);
    });

    test('different string value -> not equal', () {
      expect(
        StructuralEquivalence.nodesEqual(_leafText('hello'), _leafText('bye')),
        isFalse,
      );
    });

    test('different hasConst -> not equal (Q3: const-aware)', () {
      expect(
        StructuralEquivalence.nodesEqual(
          _leafText('x', hasConst: true),
          _leafText('x', hasConst: false),
        ),
        isFalse,
      );
    });

    test('different child count -> not equal', () {
      final aChild = _leafText('a');
      final bChild1 = _leafText('a');
      final bChild2 = _leafText('b');
      final a = WidgetNode(
        className: 'Column',
        properties: const {},
        childSlots: {
          'children': [aChild],
        },
        sourceSpan: _someSpan,
        styleHints: const StyleHints(),
      );
      final b = WidgetNode(
        className: 'Column',
        properties: const {},
        childSlots: {
          'children': [bChild1, bChild2],
        },
        sourceSpan: _someSpan,
        styleHints: const StyleHints(),
      );
      expect(StructuralEquivalence.nodesEqual(a, b), isFalse);
    });

    test('NumLiteralValue with same value but different isDouble -> not equal',
        () {
      const a = NumLiteralValue(value: 8, isDouble: false, span: _someSpan);
      const b = NumLiteralValue(value: 8, isDouble: true, span: _someSpan);
      expect(StructuralEquivalence.propertiesEqual(a, b), isFalse);
    });

    test('different PropertyValue variants -> not equal', () {
      const a = StringLiteralValue(value: '1', span: _someSpan);
      const b = NumLiteralValue(value: 1, isDouble: false, span: _someSpan);
      expect(StructuralEquivalence.propertiesEqual(a, b), isFalse);
    });

    test('NullLiteralValue equals NullLiteralValue', () {
      const a = NullLiteralValue(span: _someSpan);
      const b = NullLiteralValue(
        span: SourceSpan(offset: 100, length: 4),
      );
      expect(StructuralEquivalence.propertiesEqual(a, b), isTrue);
    });

    test('EdgeInsetsAllValue with different isDouble -> not equal', () {
      const a = EdgeInsetsAllValue(
        amount: 8,
        amountIsDouble: false,
        span: _someSpan,
      );
      const b = EdgeInsetsAllValue(
        amount: 8,
        amountIsDouble: true,
        span: _someSpan,
      );
      expect(StructuralEquivalence.propertiesEqual(a, b), isFalse);
    });

    test('ColorValue equality ignores span, compares argbValue', () {
      const a = ColorValue(argbValue: 0xFF112233, span: _someSpan);
      const b = ColorValue(
        argbValue: 0xFF112233,
        span: SourceSpan(offset: 50, length: 20),
      );
      expect(StructuralEquivalence.propertiesEqual(a, b), isTrue);
    });

    test('EnumReferenceValue compares typeName + memberName', () {
      const a = EnumReferenceValue(
        typeName: 'Colors',
        memberName: 'blue',
        span: _someSpan,
      );
      const b = EnumReferenceValue(
        typeName: 'Colors',
        memberName: 'red',
        span: _someSpan,
      );
      expect(StructuralEquivalence.propertiesEqual(a, b), isFalse);
    });
  });
}
