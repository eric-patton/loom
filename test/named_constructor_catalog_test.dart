import 'package:loom/loom.dart';
import 'package:test/test.dart';

void main() {
  group('named-constructor recognition (catalog)', () {
    test('MaterialApp.router parses as WidgetNode with namedConstructor', () {
      const source = '''
class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'app',
      routerConfig: someConfig,
    );
  }
}
''';
      final model = parseWidgetTree(source);
      expect(model.root, isA<WidgetNode>());
      final root = model.root as WidgetNode;
      expect(root.className, equals('MaterialApp'));
      expect(root.namedConstructor, equals('router'));
      // No child slots on MaterialApp.router — routerConfig is opaque config.
      expect(root.childSlots, isEmpty);
      expect(root.properties.keys, contains('title'));
      expect(root.properties.keys, contains('routerConfig'));
    });

    test('SizedBox.expand preserves child: slot', () {
      const source = '''
class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(child: const Text('hi'));
  }
}
''';
      final model = parseWidgetTree(source);
      final root = model.root as WidgetNode;
      expect(root.className, equals('SizedBox'));
      expect(root.namedConstructor, equals('expand'));
      expect(root.childSlots.containsKey('child'), isTrue);
      final child = root.childSlots['child']!.first as WidgetNode;
      expect(child.className, equals('Text'));
    });

    test('ListView.builder is WidgetNode but has no widget slot', () {
      const source = '''
class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: 10,
      itemBuilder: (ctx, i) => const Text('x'),
    );
  }
}
''';
      final model = parseWidgetTree(source);
      final root = model.root as WidgetNode;
      expect(root.className, equals('ListView'));
      expect(root.namedConstructor, equals('builder'));
      expect(root.childSlots, isEmpty);
      expect(root.properties.keys, containsAll(['itemCount', 'itemBuilder']));
    });

    test('GridView.count keeps children: list slot', () {
      const source = '''
class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      children: [const Text('a'), const Text('b')],
    );
  }
}
''';
      final model = parseWidgetTree(source);
      final root = model.root as WidgetNode;
      expect(root.className, equals('GridView'));
      expect(root.namedConstructor, equals('count'));
      expect(root.childSlots['children'], hasLength(2));
    });

    test('DefaultTextStyle.merge preserves child: slot', () {
      const source = '''
class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle.merge(
      style: const TextStyle(),
      child: const Text('hi'),
    );
  }
}
''';
      final model = parseWidgetTree(source);
      final root = model.root as WidgetNode;
      expect(root.className, equals('DefaultTextStyle'));
      expect(root.namedConstructor, equals('merge'));
      expect(root.childSlots.containsKey('child'), isTrue);
    });

    test('unrecognized named constructor still falls to opaque', () {
      // `Foo.bar(...)` where Foo is in the catalog (or isn't) but `bar` is
      // not a registered named ctor → OpaqueNode preserves verbatim.
      const source = '''
class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp.someNonExistentNamedCtor(x: 1);
  }
}
''';
      final model = parseWidgetTree(source);
      expect(model.root, isA<OpaqueNode>());
    });

    test('instance method call on unknown receiver stays opaque', () {
      // `widget.builder()` looks like `Widget.builder(...)` syntactically.
      // The parser correctly punts because `widget` (lowercase) isn't in
      // the catalog.
      const source = '''
class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return widget.someBuilder();
  }
}
''';
      final model = parseWidgetTree(source);
      expect(model.root, isA<OpaqueNode>());
    });
  });

  group('named-constructor round-trip (serializer)', () {
    test('MaterialApp.router re-emits with namedConstructor', () {
      final node = WidgetNode(
        className: 'MaterialApp',
        namedConstructor: 'router',
        properties: const {},
        childSlots: const {},
        sourceSpan: const SourceSpan(offset: 0, length: 0),
        styleHints: const StyleHints(
          hasConst: false,
          hasNew: false,
          hasTrailingComma: false,
        ),
      );
      final out = WidgetSerializer.serialize(node);
      expect(out, equals('MaterialApp.router()'));
    });

    test('SizedBox.expand with child round-trips through serializer', () {
      final child = WidgetNode(
        className: 'Text',
        properties: const {
          'data': StringLiteralValue(
            value: 'hi',
            usesDoubleQuotes: false,
            span: SourceSpan(offset: 0, length: 0),
          ),
        },
        childSlots: const {},
        sourceSpan: const SourceSpan(offset: 0, length: 0),
        styleHints: const StyleHints(
          hasConst: true,
          hasNew: false,
          hasTrailingComma: false,
        ),
      );
      final root = WidgetNode(
        className: 'SizedBox',
        namedConstructor: 'expand',
        properties: const {},
        childSlots: {
          'child': [child],
        },
        sourceSpan: const SourceSpan(offset: 0, length: 0),
        styleHints: const StyleHints(
          hasConst: false,
          hasNew: false,
          hasTrailingComma: false,
        ),
      );
      final out = WidgetSerializer.serialize(root);
      expect(out, equals("SizedBox.expand(child: const Text('hi'))"));
    });

    test('parse → serialize preserves namedConstructor exactly', () {
      const source = '''
class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(child: const Text('hi'));
  }
}
''';
      final model = parseWidgetTree(source);
      final emitted = WidgetSerializer.serialize(model.root);
      // The serializer always emits arg keys alphabetically; the original
      // had only one arg so order is moot. Verify the named-ctor form is
      // preserved.
      expect(emitted, startsWith('SizedBox.expand('));
    });

    test('empty-edit idempotence still holds on a file with MaterialApp.router',
        () {
      const source = '''
class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: someConfig,
      title: 'app',
    );
  }
}
''';
      // Required scout invariant: applying no edits yields byte-identical
      // source. Before named-ctor support, this file's root was OpaqueNode
      // and trivially passed; now it's a modeled WidgetNode that must
      // still round-trip cleanly.
      final out = applySourceEdits(source, const <SourceEdit>[]);
      expect(out, equals(source));
    });
  });
}
