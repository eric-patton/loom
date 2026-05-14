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

    test('string literal - escapes dollar sign', () {
      const v = StringLiteralValue(value: r'price: $5', span: _span);
      expect(PropertySerializer.serialize(v), equals(r"'price: \$5'"));
    });

    test('string literal - escapes newline', () {
      const v = StringLiteralValue(value: 'line1\nline2', span: _span);
      expect(PropertySerializer.serialize(v), equals(r"'line1\nline2'"));
    });

    test('string literal - escapes tab, carriage return, backspace', () {
      const v = StringLiteralValue(value: '\t\r\b', span: _span);
      expect(PropertySerializer.serialize(v), equals(r"'\t\r\b'"));
    });

    test('string literal - escapes low control chars as \\xHH', () {
      final v = StringLiteralValue(
        value: String.fromCharCodes(const [0x01, 0x1F]),
        span: _span,
      );
      expect(PropertySerializer.serialize(v), equals(r"'\x01\x1f'"));
    });

    test('string literal - double-quoted preserves style and inverts escaping',
        () {
      const v = StringLiteralValue(
        value: "she said 'hi'",
        span: _span,
        usesDoubleQuotes: true,
      );
      expect(
        PropertySerializer.serialize(v),
        equals('"she said \'hi\'"'),
        reason: 'single quotes inside double-quoted string are NOT escaped',
      );
    });

    test('string literal - double-quoted escapes inner double quotes', () {
      const v = StringLiteralValue(
        value: 'she said "hi"',
        span: _span,
        usesDoubleQuotes: true,
      );
      expect(PropertySerializer.serialize(v), equals(r'"she said \"hi\""'));
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

    test('NumLiteralValue NaN -> ArgumentError', () {
      const v = NumLiteralValue(value: double.nan, isDouble: true, span: _span);
      expect(() => PropertySerializer.serialize(v), throwsArgumentError);
    });

    test('NumLiteralValue infinity -> ArgumentError', () {
      const v = NumLiteralValue(
        value: double.infinity,
        isDouble: true,
        span: _span,
      );
      expect(() => PropertySerializer.serialize(v), throwsArgumentError);
    });

    test('ColorValue negative -> ArgumentError', () {
      const v = ColorValue(argbValue: -1, span: _span);
      expect(() => PropertySerializer.serialize(v), throwsArgumentError);
    });

    test('ColorValue > 32 bits -> ArgumentError', () {
      const v = ColorValue(argbValue: 0x100000000, span: _span);
      expect(() => PropertySerializer.serialize(v), throwsArgumentError);
    });
  });

  group('positional-opaque round-trip', () {
    test(
      'Text(modeledArg, unmodeledArg) preserves positional order on emit',
      () {
        const source = '''
class App extends StatelessWidget {
  Widget build(BuildContext context) {
    return Text('foo', 'bar');
  }
}
''';
        final model = parseWidgetTree(source);
        final text = model.root;
        // First positional is catalog-modeled as `data`; second is opaque.
        expect(text.properties['data'], isA<StringLiteralValue>());
        expect(
          text.properties['${kPositionalOpaqueKeyPrefix}1'],
          isA<OpaquePropertyValue>(),
        );

        final serialized = WidgetSerializer.serialize(text);
        expect(serialized, contains("'foo'"));
        expect(serialized, contains("'bar'"));
        expect(
          serialized.indexOf("'foo'"),
          lessThan(serialized.indexOf("'bar'")),
          reason: 'positional args must emit in source order',
        );

        // Re-parse: the round-trip is structurally identical.
        final reparsed = parseWidgetTree(
          source.replaceAll(
            "Text('foo', 'bar')",
            serialized,
          ),
        );
        expect(
          StructuralEquivalence.equal(reparsed, model),
          isTrue,
          reason: '$serialized must reparse to an equivalent model',
        );
      },
    );
  });

  group('applySourceEdits validation', () {
    test('negative offset throws ArgumentError', () {
      expect(
        () => applySourceEdits('abc', [
          const SourceEdit(offset: -1, length: 0, replacement: 'X'),
        ]),
        throwsArgumentError,
      );
    });

    test('out-of-bounds range throws ArgumentError', () {
      expect(
        () => applySourceEdits('abc', [
          const SourceEdit(offset: 0, length: 10, replacement: 'X'),
        ]),
        throwsArgumentError,
      );
    });

    test('overlapping edits throw ArgumentError', () {
      expect(
        () => applySourceEdits('abcdef', [
          const SourceEdit(offset: 0, length: 3, replacement: 'X'),
          const SourceEdit(offset: 2, length: 3, replacement: 'Y'),
        ]),
        throwsArgumentError,
      );
    });

    test('two pure-insert edits at the same offset throw ArgumentError', () {
      expect(
        () => applySourceEdits('abc', [
          const SourceEdit(offset: 1, length: 0, replacement: 'X'),
          const SourceEdit(offset: 1, length: 0, replacement: 'Y'),
        ]),
        throwsArgumentError,
      );
    });

    test('adjacent non-overlapping edits succeed', () {
      final out = applySourceEdits('abcdef', [
        const SourceEdit(offset: 0, length: 2, replacement: 'X'),
        const SourceEdit(offset: 2, length: 2, replacement: 'Y'),
      ]);
      expect(out, equals('XYef'));
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

  group('EditPlanner structural edits', () {
    WidgetNode mkChild(String data) => WidgetNode(
          className: 'Text',
          properties: {
            'data': StringLiteralValue(value: data, span: _span),
          },
          childSlots: const {},
          sourceSpan: _span,
          styleHints: const StyleHints(),
        );

    test('insertChild at end of a multi-line trailing-comma list', () {
      const source = '''
class App extends StatelessWidget {
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('a'),
        Text('b'),
      ],
    );
  }
}
''';
      final model = parseWidgetTree(source);
      final column = model.root;
      final edit = EditPlanner.insertChildEdit(
        parent: column,
        slotName: 'children',
        index: 2,
        newChild: mkChild('c'),
        source: source,
      );
      final newSource = applySourceEdits(source, [edit]);
      expect(newSource.contains("Text('c')"), isTrue);
      // Reparses cleanly and has 3 children.
      final reparsed = parseWidgetTree(newSource);
      expect(reparsed.root.childSlots['children'], hasLength(3));
      // Reparsed last child has data 'c'.
      final lastChild =
          reparsed.root.childSlots['children']!.last as WidgetNode;
      final lastData = lastChild.properties['data']! as StringLiteralValue;
      expect(lastData.value, equals('c'));
    });

    test('removeChild on middle element of a list', () {
      const source = '''
class App extends StatelessWidget {
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('a'),
        Text('b'),
        Text('c'),
      ],
    );
  }
}
''';
      final model = parseWidgetTree(source);
      final column = model.root;
      final edit = EditPlanner.removeChildEdit(
        parent: column,
        slotName: 'children',
        index: 1,
        source: source,
      );
      final newSource = applySourceEdits(source, [edit]);
      expect(newSource.contains("Text('b')"), isFalse);
      final reparsed = parseWidgetTree(newSource);
      expect(reparsed.root.childSlots['children'], hasLength(2));
    });

    test('removeChild on only element contracts list to empty', () {
      const source = '''
class App extends StatelessWidget {
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('only'),
      ],
    );
  }
}
''';
      final model = parseWidgetTree(source);
      final edit = EditPlanner.removeChildEdit(
        parent: model.root,
        slotName: 'children',
        index: 0,
        source: source,
      );
      final newSource = applySourceEdits(source, [edit]);
      final reparsed = parseWidgetTree(newSource);
      expect(reparsed.root.childSlots['children'], isEmpty);
    });

    test(
      'withProperty throws OpaqueEditException when path descends into '
      'an OpaqueNode',
      () {
        // Theme.of(...) is not a widget constructor; the visitor lands
        // it as OpaqueNode inside the children list.
        const source = '''
class App extends StatelessWidget {
  Widget build(BuildContext context) {
    return Column(
      children: [
        Theme.of(context).platform,
      ],
    );
  }
}
''';
        final model = parseWidgetTree(source);
        expect(
          model.root.childSlots['children']!.first,
          isA<OpaqueNode>(),
          reason: 'precondition: the entry must be opaque',
        );

        // Descending INTO the opaque entry throws.
        expect(
          () => model.withProperty(
            const [
              (slot: 'children', index: 0),
              (slot: 'whatever', index: 0),
            ],
            'data',
            const StringLiteralValue(
              value: 'x',
              span: SourceSpan(offset: 0, length: 0),
            ),
          ),
          throwsA(isA<OpaqueEditException>()),
        );
      },
    );

    test(
        'removeChild preserves trailing line comment after deleted first element',
        () {
      const source = '''
class App extends StatelessWidget {
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('a'), // important
        Text('b'),
      ],
    );
  }
}
''';
      final model = parseWidgetTree(source);
      final edit = EditPlanner.removeChildEdit(
        parent: model.root,
        slotName: 'children',
        index: 0,
        source: source,
      );
      final newSource = applySourceEdits(source, [edit]);
      expect(
        newSource.contains('// important'),
        isTrue,
        reason: 'line comment must survive the first-element removal',
      );
      expect(newSource.contains("Text('a')"), isFalse);
    });

    test(
      'removeChild preserves block comment between elements (middle removal)',
      () {
        const source = '''
class App extends StatelessWidget {
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('a'),
        Text('b'), /* about c */
        Text('c'),
      ],
    );
  }
}
''';
        final model = parseWidgetTree(source);
        final edit = EditPlanner.removeChildEdit(
          parent: model.root,
          slotName: 'children',
          index: 1,
          source: source,
        );
        final newSource = applySourceEdits(source, [edit]);
        expect(
          newSource.contains('/* about c */'),
          isTrue,
          reason: 'block comment must survive middle-element removal',
        );
        expect(newSource.contains("Text('b')"), isFalse);
      },
    );

    test(
      'insertChild does not duplicate a comment in the inter-element separator',
      () {
        const source = '''
class App extends StatelessWidget {
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('a'), // first
        Text('b'),
      ],
    );
  }
}
''';
        final model = parseWidgetTree(source);
        final newChild = WidgetNode(
          className: 'Text',
          properties: {
            'data': StringLiteralValue(value: 'c', span: _span),
          },
          childSlots: const {},
          sourceSpan: _span,
          styleHints: const StyleHints(),
        );
        final edit = EditPlanner.insertChildEdit(
          parent: model.root,
          slotName: 'children',
          index: 1,
          newChild: newChild,
          source: source,
        );
        final newSource = applySourceEdits(source, [edit]);
        // The natural inter-element separator here is `, // first\n        `
        // — emitting that around every inserted element would duplicate the
        // comment. The fallback default `,\n  ` should be used instead.
        final firstCount = '// first'.allMatches(newSource).length;
        expect(
          firstCount,
          equals(1),
          reason: 'comment must not be duplicated on insert',
        );
        expect(newSource.contains("Text('c')"), isTrue);
      },
    );

    test('moveChild swaps source positions of two siblings', () {
      const source = '''
class App extends StatelessWidget {
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('alpha'),
        Text('beta'),
        Text('gamma'),
      ],
    );
  }
}
''';
      final model = parseWidgetTree(source);
      final edits = EditPlanner.moveChildEdits(
        parent: model.root,
        slotName: 'children',
        from: 0,
        to: 2,
        source: source,
      );
      final newSource = applySourceEdits(source, edits);
      final reparsed = parseWidgetTree(newSource);
      final kids = reparsed.root.childSlots['children']!.cast<WidgetNode>();
      expect(
        kids.map((c) => (c.properties['data']! as StringLiteralValue).value),
        equals(['beta', 'gamma', 'alpha']),
      );
    });
  });

  group('WidgetSerializer', () {
    test('serializes a plain Text', () {
      final w = WidgetNode(
        className: 'Text',
        properties: {
          'data': StringLiteralValue(value: 'hi', span: _span),
        },
        childSlots: const {},
        sourceSpan: _span,
        styleHints: const StyleHints(),
      );
      expect(WidgetSerializer.serialize(w), equals("Text('hi')"));
    });

    test('serializes a const Text with trailing comma', () {
      final w = WidgetNode(
        className: 'Text',
        properties: {
          'data': StringLiteralValue(value: 'hi', span: _span),
        },
        childSlots: const {},
        sourceSpan: _span,
        styleHints: const StyleHints(hasConst: true, hasTrailingComma: true),
      );
      expect(WidgetSerializer.serialize(w), equals("const Text('hi',)"));
    });

    test('serializes Padding with EdgeInsets.all and child Text', () {
      final w = WidgetNode(
        className: 'Padding',
        properties: {
          'padding': EdgeInsetsAllValue(
            amount: 8,
            amountIsDouble: true,
            span: _span,
          ),
        },
        childSlots: {
          'child': [
            WidgetNode(
              className: 'Text',
              properties: {
                'data': StringLiteralValue(value: 'x', span: _span),
              },
              childSlots: const {},
              sourceSpan: _span,
              styleHints: const StyleHints(),
            ),
          ],
        },
        sourceSpan: _span,
        styleHints: const StyleHints(),
      );
      // child is single-shaped; child slot rendered as `child: <widget>`.
      expect(
        WidgetSerializer.serialize(w),
        equals("Padding(child: Text('x'), padding: EdgeInsets.all(8.0))"),
      );
    });

    test('serializes an OpaqueNode as its sourceText', () {
      const o = OpaqueNode(
        sourceSpan: SourceSpan(offset: 0, length: 12),
        sourceText: '_helper()',
      );
      expect(WidgetSerializer.serialize(o), equals('_helper()'));
    });

    test('serializes a MethodReferenceNode as methodName()', () {
      const m = MethodReferenceNode(
        methodName: '_buildHeader',
        callSourceSpan: SourceSpan(offset: 0, length: 0),
        body: OpaqueNode(
          sourceSpan: SourceSpan(offset: 0, length: 0),
          sourceText: '',
        ),
      );
      expect(WidgetSerializer.serialize(m), equals('_buildHeader()'));
    });
  });
}
