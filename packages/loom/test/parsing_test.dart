import 'dart:io';

import 'package:loom/loom.dart';
import 'package:test/test.dart';

void main() {
  late String source;
  late WidgetTreeModel model;
  late WidgetNode root;

  setUpAll(() {
    source = File('test/fixtures/simple_widget.dart').readAsStringSync();
    model = parseWidgetTree(source);
    root = model.root as WidgetNode;
  });

  group('parseWidgetTree on simple_widget.dart', () {
    List<WidgetNode> children(WidgetNode node) =>
        (node.childSlots['children'] ?? const <ModelNode>[])
            .whereType<WidgetNode>()
            .toList();

    test('root is Column', () {
      expect(root.className, equals('Column'));
    });

    test('Column has four children', () {
      expect(children(root), hasLength(4));
    });

    test('first child is const Text with the greeting', () {
      final first = children(root)[0];
      expect(first.className, equals('Text'));
      expect(first.styleHints.hasConst, isTrue);

      final data = first.properties['data'];
      if (data is! StringLiteralValue) {
        fail('expected StringLiteralValue for data, got ${data.runtimeType}');
      }
      expect(data.value, equals('Hello, world!'));
    });

    test('second child is const Padding with EdgeInsets.all(8.0)', () {
      final padding = children(root)[1];
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
      final padding = children(root)[2];
      expect(padding.className, equals('Padding'));

      final pad = padding.properties['padding'];
      if (pad is! EdgeInsetsAllValue) {
        fail('expected EdgeInsetsAllValue, got ${pad.runtimeType}');
      }
      expect(pad.amount, equals(16));
      expect(pad.amountIsDouble, isFalse);
    });

    test('last child Text has no const keyword', () {
      final last = children(root).last;
      expect(last.className, equals('Text'));
      expect(last.styleHints.hasConst, isFalse);

      final data = last.properties['data'];
      if (data is! StringLiteralValue) {
        fail('expected StringLiteralValue, got ${data.runtimeType}');
      }
      expect(data.value, equals('Final entry without const'));
    });

    test('inner Text inside const Padding has no explicit const', () {
      final padding = children(root)[1];
      final innerText = padding.childSlots['child']!.first as WidgetNode;
      expect(innerText.className, equals('Text'));
      expect(innerText.styleHints.hasConst, isFalse);
    });

    test('Column has a trailing comma; single-arg Text does not', () {
      expect(root.styleHints.hasTrailingComma, isTrue);
      expect(children(root)[0].styleHints.hasTrailingComma, isFalse);
    });

    test('multi-line Column captures isMultiLine; single-line Text does not',
        () {
      // The Column in simple_widget.dart spans multiple lines; its single
      // children render on separate lines. Each individual Text(...) call
      // fits on one line.
      expect(root.styleHints.isMultiLine, isTrue,
          reason: 'Column(...) spans multiple lines');
      expect(children(root)[0].styleHints.isMultiLine, isFalse,
          reason: 'first Text("Hello, world!") fits on one line');
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

      collect(root);
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
      final data = (model.root as WidgetNode).properties['data'];
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
      final data = (model.root as WidgetNode).properties['data'];
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
      final data = (model.root as WidgetNode).properties['data'];
      expect(data, isA<OpaquePropertyValue>());
    });
  });

  group('Q4 parse diagnostics', () {
    test('clean source has an empty diagnostics list', () {
      const source = '''
class App extends StatelessWidget {
  Widget build(BuildContext context) {
    return const Text('hi');
  }
}
''';
      final model = parseWidgetTree(source);
      expect(model.diagnostics, isEmpty);
    });

    test(
      'source with syntax errors surfaces diagnostics but the model still '
      'represents what could be error-recovered',
      () {
        // Missing close paren on `Text('hi'` — analyzer error-recovers.
        const source = '''
class App extends StatelessWidget {
  Widget build(BuildContext context) {
    return const Text('hi'
  }
}
''';
        final model = parseWidgetTree(source);
        // Diagnostics list is non-empty — UI consumers can choose to
        // show a warning or refuse edits while errors are present.
        expect(model.diagnostics, isNotEmpty);
        // Each diagnostic carries a SourceSpan pointing into the
        // problem location.
        for (final diag in model.diagnostics) {
          expect(diag.span.offset, greaterThanOrEqualTo(0));
          expect(diag.message, isNotEmpty);
        }
      },
    );
  });

  group('M5 helper-method following', () {
    test('helpers resolve to MethodReferenceNode with body widget tree', () {
      final source = File(
        'test/fixtures/helper_methods.dart',
      ).readAsStringSync();
      final model = parseWidgetTree(source);

      // Root: Column with children [MethodRef(_buildTitle), MethodRef(_buildContent)]
      final rootChildren = (model.root as WidgetNode).childSlots['children']!;
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
      'bare-helper-root build() => _self() now lands as an OpaqueNode '
      'root (multi-reference defense catches self-recursion)',
      () {
        // Pre-M5.2: `WidgetTreeModel.root: WidgetNode` rejected this
        // shape and `parseWidgetTree` threw.
        // M5.3: root is widened to `ModelNode`. The multi-reference
        // defense at parse time still drops `_self` from the helper
        // map (self-call inside the helper body counts as a second
        // reference), so the build-root `_self()` falls through to
        // OpaqueNode.
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
        expect(
          model.root,
          isA<OpaqueNode>(),
          reason: '_self is multi-referenced (build calls it AND its own '
              'body calls it), so both references fall through to opaque',
        );
        expect((model.root as OpaqueNode).sourceText, equals('_self()'));
      },
    );

    test(
      'bare-helper-root build() => _h() resolves to a MethodReferenceNode '
      'root when _h has a single reference',
      () {
        const source = '''
import 'package:flutter/material.dart';

class App extends StatelessWidget {
  const App({super.key});

  Widget _h() {
    return const Text('root');
  }

  @override
  Widget build(BuildContext context) {
    return _h();
  }
}
''';
        final model = parseWidgetTree(source);
        expect(
          model.root,
          isA<MethodReferenceNode>(),
          reason: 'bare-helper-root must resolve at the root, not throw',
        );
        final m = model.root as MethodReferenceNode;
        expect(m.methodName, equals('_h'));
        expect(m.body, isA<WidgetNode>());
        expect((m.body as WidgetNode).className, equals('Text'));
      },
    );

    test(
      'self-recursive helper becomes opaque at every reference '
      '(multi-reference defense)',
      () {
        // Recursive helper: `_self()` appears in both build() and
        // `_self`'s own body, so it's referenced more than once across
        // the analyzed scope. The parser's multi-reference defense
        // drops it from the helper-method map before the visitor runs,
        // so every reference falls through to `OpaqueNode`.
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
        final rootChildren = (model.root as WidgetNode).childSlots['children']!;
        expect(rootChildren, hasLength(1));
        expect(
          rootChildren[0],
          isA<OpaqueNode>(),
          reason: 'multi-referenced (including self-recursive) helpers are '
              'opaque at every reference',
        );
      },
    );

    test('indirect-cycle helpers (a -> b -> a) all become opaque', () {
      // _a is called from build() AND from _b's body → multi-reference.
      // _b is called only from _a's body → single reference. But _a's
      // multi-reference makes ALL references to _a opaque, so _a's
      // body is never resolved, so _b is effectively unreferenced from
      // the modeled tree (still defined in source, just not modeled).
      const source = '''
import 'package:flutter/material.dart';

class IndirectCycle extends StatelessWidget {
  const IndirectCycle({super.key});

  Widget _a() {
    return _b();
  }

  Widget _b() {
    return _a();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _a(),
      ],
    );
  }
}
''';
      final model = parseWidgetTree(source);
      final rootChildren = (model.root as WidgetNode).childSlots['children']!;
      expect(rootChildren, hasLength(1));
      expect(
        rootChildren[0],
        isA<OpaqueNode>(),
        reason:
            'indirect-cycle: _a is called more than once (build + _b body), '
            'so the multi-reference defense kicks in for _a at every call '
            'site, never resolving _a or following into _b',
      );
    });

    test('multi-referenced helper opaque at every call site', () {
      const source = '''
import 'package:flutter/material.dart';

class MultiRef extends StatelessWidget {
  const MultiRef({super.key});

  Widget _h() {
    return const Text('shared');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _h(),
        _h(),
      ],
    );
  }
}
''';
      final model = parseWidgetTree(source);
      final rootChildren = (model.root as WidgetNode).childSlots['children']!;
      expect(rootChildren, hasLength(2));
      expect(rootChildren[0], isA<OpaqueNode>());
      expect(rootChildren[1], isA<OpaqueNode>());
    });

    test(
      'non-widget-position call to a helper does not count as a reference '
      '(widget-position-aware counter)',
      () {
        // Round-2 finding #6: the old RecursiveAstVisitor counter
        // recursed into property values and method-call targets,
        // counting `_h()` even where the visitor would treat it as
        // opaque (never a MethodReferenceNode candidate). That over-
        // counted to 2+ and falsely dropped the legitimate widget-
        // position call site too.
        //
        // Here `_h()` appears ONCE at a widget position (root return)
        // and ONCE inside a property-position OpaquePropertyValue
        // (`onPressed: _h`). With widget-position-aware counting, the
        // widget-position call resolves to MethodReferenceNode.
        //
        // Tearoff and call inside an opaque arg both count as non-
        // widget positions per the visitor's logic.
        const source = '''
import 'package:flutter/material.dart';

class App extends StatelessWidget {
  const App({super.key});

  Widget _h() {
    return const Text('hi');
  }

  @override
  Widget build(BuildContext context) {
    return Container(child: _h(), foo: someFunc(_h()));
  }
}
''';
        final model = parseWidgetTree(source);
        // _h() inside Container.child is widget-position → MethodRef.
        final inner = (model.root as WidgetNode).childSlots['child']!.first;
        expect(
          inner,
          isA<MethodReferenceNode>(),
          reason: '_h() at widget position should resolve, since the '
              'non-widget-position _h() inside someFunc(_h()) does not '
              'count toward the multi-reference limit',
        );
      },
    );

    test(
      'helper called with type arguments falls through to opaque '
      '(_h<int>() does not resolve as MethodReferenceNode)',
      () {
        // Round-2 finding #9: visitor used to ignore typeArguments and
        // resolve `_h<int>()` to MethodReferenceNode, then re-emit as
        // `_h()` — dropping the type args. Now: falls through to opaque.
        const source = '''
import 'package:flutter/material.dart';

class App extends StatelessWidget {
  const App({super.key});

  Widget _h<T>() {
    return const Text('hi');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _h<int>(),
      ],
    );
  }
}
''';
        final model = parseWidgetTree(source);
        final children = (model.root as WidgetNode).childSlots['children']!;
        expect(children, hasLength(1));
        expect(
          children[0],
          isA<OpaqueNode>(),
          reason: 'type-argumented helper call must be opaque so source '
              'bytes (with type args) round-trip verbatim',
        );
        expect(
          (children[0] as OpaqueNode).sourceText,
          equals('_h<int>()'),
        );
      },
    );

    test('edits to a widget inside a helper target the helper source', () {
      final source = File(
        'test/fixtures/helper_methods.dart',
      ).readAsStringSync();
      final model = parseWidgetTree(source);

      // Navigate to _buildTitle().body.Padding.child.Text and edit data.
      final titleRef = (model.root as WidgetNode).childSlots['children']![0]
          as MethodReferenceNode;
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

  group('type-argumented constructor calls fall to OpaqueNode', () {
    // Regression: tryExtractCall didn't check for type arguments on
    // InstanceCreationExpression or MethodInvocation. The serializer doesn't
    // carry type-arg info, so a modeled type-argumented constructor would
    // silently lose its `<...>` on re-emission — a round-trip violation.
    // Now they fall through to OpaqueNode and the bytes survive verbatim.

    test('Class<T>() InstanceCreation goes opaque (root)', () {
      const source = '''
class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const SizedBox<int>();
  }
}
''';
      final model = parseWidgetTree(source);
      expect(
        model.root,
        isA<OpaqueNode>(),
        reason: 'SizedBox<int>() must NOT model as SizedBox WidgetNode',
      );
    });

    test('Class<T>() in a children slot stays opaque', () {
      const source = '''
class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(children: [SizedBox<int>()]);
  }
}
''';
      final model = parseWidgetTree(source);
      final root = model.root as WidgetNode;
      expect(root.className, equals('Column'));
      final child = root.childSlots['children']!.first;
      expect(child, isA<OpaqueNode>());
    });

    test('Class<T>.named() InstanceCreation goes opaque', () {
      // Currently SizedBox.expand has no type args in framework; but parsing
      // intentionally rejects the type-args + named-ctor combo on principle.
      const source = '''
class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox<int>.expand(child: const Text('hi'));
  }
}
''';
      final model = parseWidgetTree(source);
      expect(model.root, isA<OpaqueNode>());
    });

    test('empty-edit idempotence holds on a type-argumented call', () {
      const source = '''
class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const SizedBox<int>();
  }
}
''';
      // Opaque root means the bytes are preserved verbatim — empty-edit
      // idempotence is trivial via applySourceEdits's empty-list path.
      expect(applySourceEdits(source, const <SourceEdit>[]), equals(source));
    });
  });

  // ----------------------------------------------------------------
  // Negative numeric literals: `Container(width: -4)` /
  // `EdgeInsets.all(-8.0)` previously fell to OpaquePropertyValue,
  // blocking the editor's property inspector from exposing them.
  // ----------------------------------------------------------------
  group('negative numeric literals', () {
    test('negative integer in a property → NumLiteralValue(-8)', () {
      const source = '''
class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(width: -8);
  }
}
''';
      final model = parseWidgetTree(source);
      final root = model.root as WidgetNode;
      expect(root.className, equals('Container'));
      final width = root.properties['width'];
      expect(width, isA<NumLiteralValue>());
      final n = width! as NumLiteralValue;
      expect(n.value, equals(-8));
      expect(n.isDouble, isFalse);
    });

    test('negative double in a property → NumLiteralValue(-4.5, isDouble=true)',
        () {
      const source = '''
class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(width: -4.5);
  }
}
''';
      final model = parseWidgetTree(source);
      final root = model.root as WidgetNode;
      final width = root.properties['width']! as NumLiteralValue;
      expect(width.value, equals(-4.5));
      expect(width.isDouble, isTrue);
    });

    test('EdgeInsets.all(-8.0) is recognized as EdgeInsetsAllValue', () {
      const source = '''
class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.all(-8.0), child: const Text('x'));
  }
}
''';
      final model = parseWidgetTree(source);
      final root = model.root as WidgetNode;
      final padding = root.properties['padding'];
      expect(padding, isA<EdgeInsetsAllValue>());
      final p = padding! as EdgeInsetsAllValue;
      expect(p.amount, equals(-8.0));
      expect(p.amountIsDouble, isTrue);
    });

    test('round-trip preserves negative literal bytes verbatim', () {
      const source = '''
class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(width: -8, height: -4.5);
  }
}
''';
      expect(applySourceEdits(source, const <SourceEdit>[]), equals(source));
    });

    test('non-minus prefix expressions still fall to opaque', () {
      // `!flag`, `~bits`, `++i` aren't numeric literals — keep them opaque.
      const source = '''
class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(width: ~0);
  }
}
''';
      final model = parseWidgetTree(source);
      final root = model.root as WidgetNode;
      expect(root.properties['width'], isA<OpaquePropertyValue>());
    });
  });
}
