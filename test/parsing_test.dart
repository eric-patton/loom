import 'dart:io';

import 'package:loom/loom.dart';
import 'package:test/test.dart';

void main() {
  late String source;
  late WidgetTreeModel model;

  setUpAll(() {
    source = File('test/fixtures/simple_widget.dart').readAsStringSync();
    model = parseWidgetTree(source);
  });

  group('parseWidgetTree on simple_widget.dart', () {
    List<WidgetNode> children(WidgetNode node) =>
        node.childSlots['children'] ?? const <WidgetNode>[];

    test('root is Column', () {
      expect(model.root.className, equals('Column'));
    });

    test('Column has four children', () {
      expect(children(model.root), hasLength(4));
    });

    test('first child is const Text with the greeting', () {
      final first = children(model.root)[0];
      expect(first.className, equals('Text'));
      expect(first.styleHints.hasConst, isTrue);

      final data = first.properties['data'];
      if (data is! StringLiteralValue) {
        fail('expected StringLiteralValue for data, got ${data.runtimeType}');
      }
      expect(data.value, equals('Hello, world!'));
    });

    test('second child is const Padding with EdgeInsets.all(8.0)', () {
      final padding = children(model.root)[1];
      expect(padding.className, equals('Padding'));
      expect(padding.styleHints.hasConst, isTrue);
      expect(padding.styleHints.hasTrailingComma, isTrue);

      final pad = padding.properties['padding'];
      if (pad is! EdgeInsetsAllValue) {
        fail(
          'expected EdgeInsetsAllValue for padding, got ${pad.runtimeType}',
        );
      }
      expect(pad.amount, equals(8.0));
      expect(pad.amountIsDouble, isTrue);

      final childSlot = padding.childSlots['child'];
      expect(childSlot, hasLength(1));
      expect(childSlot!.first.className, equals('Text'));
    });

    test('third child uses an integer literal in EdgeInsets.all', () {
      final padding = children(model.root)[2];
      expect(padding.className, equals('Padding'));

      final pad = padding.properties['padding'];
      if (pad is! EdgeInsetsAllValue) {
        fail('expected EdgeInsetsAllValue, got ${pad.runtimeType}');
      }
      expect(pad.amount, equals(16));
      expect(pad.amountIsDouble, isFalse);
    });

    test('last child Text has no const keyword', () {
      final last = children(model.root).last;
      expect(last.className, equals('Text'));
      expect(last.styleHints.hasConst, isFalse);

      final data = last.properties['data'];
      if (data is! StringLiteralValue) {
        fail('expected StringLiteralValue, got ${data.runtimeType}');
      }
      expect(data.value, equals('Final entry without const'));
    });

    test('inner Text inside const Padding has no explicit const', () {
      final padding = children(model.root)[1];
      final innerText = padding.childSlots['child']!.first;
      expect(innerText.className, equals('Text'));
      expect(innerText.styleHints.hasConst, isFalse);
    });

    test('Column has a trailing comma; single-arg Text does not', () {
      expect(model.root.styleHints.hasTrailingComma, isTrue);
      expect(children(model.root)[0].styleHints.hasTrailingComma, isFalse);
    });

    test('every node has a valid SourceSpan', () {
      final allNodes = <WidgetNode>[];
      void collect(WidgetNode node) {
        allNodes.add(node);
        for (final slot in node.childSlots.values) {
          for (final child in slot) {
            collect(child);
          }
        }
      }

      collect(model.root);
      expect(allNodes, isNotEmpty);

      for (final node in allNodes) {
        expect(
          node.sourceSpan.length,
          greaterThan(0),
          reason: '${node.className} span has zero length',
        );
        expect(
          node.sourceSpan.offset,
          greaterThanOrEqualTo(0),
          reason: '${node.className} span has negative offset',
        );
        expect(
          node.sourceSpan.end,
          lessThanOrEqualTo(source.length),
          reason: '${node.className} span extends past source end',
        );
      }
    });
  });
}
