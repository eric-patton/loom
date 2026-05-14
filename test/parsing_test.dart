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
        (node.childSlots['children'] ?? const <ModelNode>[])
            .whereType<WidgetNode>()
            .toList();

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
      final innerText = childSlot!.first as WidgetNode;
      expect(innerText.className, equals('Text'));
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
      final innerText = padding.childSlots['child']!.first as WidgetNode;
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
            if (child is WidgetNode) {
              collect(child);
            }
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

  group('string fidelity', () {
    test('double-quoted string keeps usesDoubleQuotes=true', () {
      const source = '''
class App extends StatelessWidget {
  Widget build(BuildContext context) {
    return const Text("hi");
  }
}
''';
      final model = parseWidgetTree(source);
      final data = model.root.properties['data'];
      expect(data, isA<StringLiteralValue>());
      expect((data as StringLiteralValue).value, equals('hi'));
      expect(data.usesDoubleQuotes, isTrue);
    });

    test('raw string lands in OpaquePropertyValue', () {
      const source = r'''
class App extends StatelessWidget {
  Widget build(BuildContext context) {
    return Text(r'C:\path');
  }
}
''';
      final model = parseWidgetTree(source);
      final data = model.root.properties['data'];
      expect(data, isA<OpaquePropertyValue>());
      expect((data as OpaquePropertyValue).sourceText, equals(r"r'C:\path'"));
    });

    test('triple-quoted string lands in OpaquePropertyValue', () {
      const source = '''
class App extends StatelessWidget {
  Widget build(BuildContext context) {
    return Text(\'\'\'hi\'\'\');
  }
}
''';
      final model = parseWidgetTree(source);
      final data = model.root.properties['data'];
      expect(data, isA<OpaquePropertyValue>());
    });
  });

  group('M5 helper-method following', () {
    test('helpers resolve to MethodReferenceNode with body widget tree', () {
      final source = File(
        'test/fixtures/helper_methods.dart',
      ).readAsStringSync();
      final model = parseWidgetTree(source);

      // Root: Column with children [MethodRef(_buildTitle), MethodRef(_buildContent)]
      final rootChildren = model.root.childSlots['children']!;
      expect(rootChildren, hasLength(2));

      final first = rootChildren[0];
      if (first is! MethodReferenceNode) {
        fail('expected MethodReferenceNode, got ${first.runtimeType}');
      }
      expect(first.methodName, equals('_buildTitle'));
      expect(first.body, isA<WidgetNode>());
      expect((first.body as WidgetNode).className, equals('Padding'));

      final second = rootChildren[1];
      if (second is! MethodReferenceNode) {
        fail('expected MethodReferenceNode, got ${second.runtimeType}');
      }
      expect(second.methodName, equals('_buildContent'));
      expect((second.body as WidgetNode).className, equals('Column'));
    });

    test(
      'cyclic helper (helper calls itself) terminates with inner OpaqueNode',
      () {
        const source = '''
import 'package:flutter/material.dart';

class Cycle extends StatelessWidget {
  const Cycle({super.key});

  Widget _self() {
    return _self();
  }

  @override
  Widget build(BuildContext context) {
    return _self();
  }
}
''';
        final model = parseWidgetTree(source);

        // Root is the outer MethodReferenceNode for _self().
        final root = model.root;
        // model.root is WidgetTreeModel.root (WidgetNode), but in this
        // fixture build() directly returns _self() — which resolves to a
        // MethodReferenceNode, NOT a WidgetNode. Our parser requires the
        // root to be WidgetNode (convertWidget throws if root is
        // anything else). So we don't expect a passing model build for
        // a build() that ONLY returns a helper call.
        //
        // Instead, parseWidgetTree throws. The cycle-detection check is
        // observable when the helper is INSIDE another modelable widget.
        // Verified by the next assertion.
        expect(root.className, isNotEmpty);
      },
      skip: 'requires a build() that wraps _self() inside a modelable widget; '
          'see the wrapped variant below',
    );

    test('cyclic helper inside a wrapping widget produces inner OpaqueNode',
        () {
      const source = '''
import 'package:flutter/material.dart';

class Cycle extends StatelessWidget {
  const Cycle({super.key});

  Widget _self() {
    return Padding(
      padding: const EdgeInsets.all(4.0),
      child: _self(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _self(),
      ],
    );
  }
}
''';
      final model = parseWidgetTree(source);
      final rootChildren = model.root.childSlots['children']!;
      expect(rootChildren, hasLength(1));

      final ref = rootChildren[0];
      if (ref is! MethodReferenceNode) {
        fail('expected MethodReferenceNode, got ${ref.runtimeType}');
      }
      expect(ref.methodName, equals('_self'));

      // The body is a Padding...
      final padding = ref.body as WidgetNode;
      expect(padding.className, equals('Padding'));
      // ...whose `child` slot would have been _self() again, but the
      // cycle detector kicks in and emits an OpaqueNode at the inner
      // reference.
      final innerChild = padding.childSlots['child']!.first;
      expect(
        innerChild,
        isA<OpaqueNode>(),
        reason: 'cycle stop: inner _self() should be opaque',
      );
    });

    test('edits to a widget inside a helper target the helper source', () {
      final source = File(
        'test/fixtures/helper_methods.dart',
      ).readAsStringSync();
      final model = parseWidgetTree(source);

      // Navigate to _buildTitle().body.Padding.child.Text and edit data.
      final titleRef =
          model.root.childSlots['children']![0] as MethodReferenceNode;
      final padding = titleRef.body as WidgetNode;
      final innerText = padding.childSlots['child']!.first as WidgetNode;
      final oldData = innerText.properties['data']! as StringLiteralValue;

      // The Text's sourceSpan should point inside _buildTitle's BODY,
      // not at the call site in build(). _buildTitle is the first
      // method in the file, so its Text is way before the build()'s
      // call site.
      expect(
        innerText.sourceSpan.offset,
        lessThan(titleRef.callSourceSpan.offset),
        reason: 'inner Text span should be in helper definition, '
            'BEFORE the call site at build()',
      );

      // Edit via path and verify it touches the helper's source.
      const newValue = StringLiteralValue(
        value: 'Updated title',
        span: SourceSpan(offset: 0, length: 0),
      );
      final edit = EditPlanner.propertyEdit(
        oldValue: oldData,
        newValue: newValue,
      );
      expect(
        edit.offset,
        lessThan(titleRef.callSourceSpan.offset),
        reason: 'edit must target the helper definition, not the call',
      );

      final newSource = applySourceEdits(source, [edit]);
      expect(newSource.contains("'Updated title'"), isTrue);
      // The call site `_buildTitle()` text in build() is untouched.
      expect(newSource.contains('_buildTitle()'), isTrue);
    });
  });
}
