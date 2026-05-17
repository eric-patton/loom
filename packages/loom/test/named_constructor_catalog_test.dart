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

    test(
        'withProperty on a descendant preserves namedConstructor on the rebuilt '
        'ancestor', () {
      // Regression: _withProperty's recursive parent-rebuild path used to omit
      // namedConstructor, silently turning SizedBox.expand into SizedBox on
      // every descendant property edit. Round-trip violation.
      const source = '''
class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: const Text('before'),
    );
  }
}
''';
      final model = parseWidgetTree(source);
      final updated = model.withProperty(
        const [(slot: 'child', index: 0)],
        'data',
        const StringLiteralValue(
          value: 'after',
          span: SourceSpan(offset: 0, length: 0),
        ),
      );
      final newRoot = updated.root as WidgetNode;
      expect(newRoot.className, equals('SizedBox'));
      expect(
        newRoot.namedConstructor,
        equals('expand'),
        reason: 'parent rebuild dropped namedConstructor',
      );
      final newChild = newRoot.childSlots['child']!.first as WidgetNode;
      expect(
        (newChild.properties['data']! as StringLiteralValue).value,
        equals('after'),
      );
    });

    test(
        'insertChild into a descendant preserves namedConstructor on rebuilt '
        'ancestor', () {
      // Same shape as the withProperty regression but for _modifySlot's
      // recursive rebuild path.
      const source = '''
class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      children: [
        const Text('a'),
      ],
    );
  }
}
''';
      final model = parseWidgetTree(source);
      final inserted = model.insertChild(
        const [],
        'children',
        1,
        WidgetNode(
          className: 'Text',
          properties: const {
            'data': StringLiteralValue(
              value: 'b',
              span: SourceSpan(offset: 0, length: 0),
            ),
          },
          childSlots: const {},
          sourceSpan: const SourceSpan(offset: 0, length: 0),
          styleHints: const StyleHints(),
        ),
      );
      // Insert into the root's `children` — root itself is GridView.count.
      // Rebuilt root still must have namedConstructor='count'.
      final newRoot = inserted.root as WidgetNode;
      expect(newRoot.className, equals('GridView'));
      expect(
        newRoot.namedConstructor,
        equals('count'),
        reason: 'root rebuild dropped namedConstructor on insertChild',
      );
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

  // ----------------------------------------------------------------
  // Phase 6 catalog expansion — slivers, dialogs, M3 nav.
  // ----------------------------------------------------------------
  group('Phase 6 catalog expansion', () {
    test('CustomScrollView slivers are modeled, not opaque', () {
      // Regression on the worst opaque-root shape from real apps:
      // every Sliver* inside a CustomScrollView.slivers list used to land
      // as an OpaqueNode, blocking the editor from showing structure
      // for the most common scrolling layout in Flutter.
      const source = '''
class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        const SliverAppBar(title: Text('Title')),
        SliverPadding(
          padding: const EdgeInsets.all(8),
          sliver: SliverList(),
        ),
        SliverToBoxAdapter(child: Container()),
        const SliverFillRemaining(child: Text('done')),
      ],
    );
  }
}
''';
      final model = parseWidgetTree(source);
      final root = model.root as WidgetNode;
      expect(root.className, equals('CustomScrollView'));
      final slivers = root.childSlots['slivers']!;
      expect(slivers, hasLength(4));
      for (final s in slivers) {
        expect(s, isA<WidgetNode>(),
            reason: 'every Sliver* should now be modeled');
      }
      expect((slivers[0] as WidgetNode).className, equals('SliverAppBar'));
      expect((slivers[1] as WidgetNode).className, equals('SliverPadding'));
      // SliverPadding.sliver is a single Widget slot.
      expect(
          (slivers[1] as WidgetNode).childSlots.containsKey('sliver'), isTrue);
    });

    test('AlertDialog actions are a list slot', () {
      const source = '''
class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Heads up'),
      content: const Text('Are you sure?'),
      actions: [
        const TextButton(child: Text('Cancel')),
        const ElevatedButton(child: Text('OK')),
      ],
    );
  }
}
''';
      final model = parseWidgetTree(source);
      final root = model.root as WidgetNode;
      expect(root.className, equals('AlertDialog'));
      expect(root.childSlots['actions']!, hasLength(2));
      expect(root.childSlots.containsKey('title'), isTrue);
      expect(root.childSlots.containsKey('content'), isTrue);
    });

    test('NavigationBar destinations are a list slot', () {
      const source = '''
class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
        NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
      ],
    );
  }
}
''';
      final model = parseWidgetTree(source);
      final root = model.root as WidgetNode;
      expect(root.className, equals('NavigationBar'));
      final dests = root.childSlots['destinations']!;
      expect(dests, hasLength(2));
      // NavigationDestination's icon slot is single.
      expect((dests[0] as WidgetNode).childSlots.containsKey('icon'), isTrue);
    });

    test('SliverAppBar.medium and .large are recognized named constructors',
        () {
      const source = '''
class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SliverAppBar.medium(
      title: const Text('Heading'),
      actions: const [Icon(Icons.search)],
    );
  }
}
''';
      final model = parseWidgetTree(source);
      final root = model.root as WidgetNode;
      expect(root.className, equals('SliverAppBar'));
      expect(root.namedConstructor, equals('medium'));
      expect(root.childSlots.containsKey('title'), isTrue);
      expect(root.childSlots['actions']!, hasLength(1));
    });

    test('ListTile leading/title/subtitle/trailing slots all recognized', () {
      const source = '''
class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.album),
      title: const Text('The Mars Volta'),
      subtitle: const Text('Frances the Mute'),
      trailing: const Icon(Icons.more_vert),
    );
  }
}
''';
      final model = parseWidgetTree(source);
      final root = model.root as WidgetNode;
      expect(root.className, equals('ListTile'));
      expect(root.childSlots.keys,
          containsAll(['leading', 'title', 'subtitle', 'trailing']));
    });

    test('BackdropFilter child is recognized', () {
      const source = '''
class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: someFilter,
      child: const Text('through blur'),
    );
  }
}
''';
      final model = parseWidgetTree(source);
      final root = model.root as WidgetNode;
      expect(root.className, equals('BackdropFilter'));
      expect(root.childSlots.containsKey('child'), isTrue);
    });

    test('Builder is recognized as a modeled root (no slots)', () {
      const source = '''
class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Builder(builder: (context) => const Text('hi'));
  }
}
''';
      final model = parseWidgetTree(source);
      // Builder has no widget-valued slots — the builder callback is
      // opaque — but the call itself is recognized so it's not OpaqueNode.
      expect(model.root, isA<WidgetNode>());
      expect((model.root as WidgetNode).className, equals('Builder'));
    });

    test('Chip family — label slot recognized', () {
      const source = '''
class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: const CircleAvatar(),
      label: const Text('Tag'),
    );
  }
}
''';
      final model = parseWidgetTree(source);
      final root = model.root as WidgetNode;
      expect(root.className, equals('Chip'));
      expect(root.childSlots.keys, containsAll(['avatar', 'label']));
    });

    test('empty-edit idempotence holds on Phase 6 widgets', () {
      const source = '''
class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        const SliverAppBar(title: Text('T')),
        SliverList.builder(itemBuilder: (c, i) => const Text('x')),
        const SliverFillRemaining(child: Text('done')),
      ],
    );
  }
}
''';
      final out = applySourceEdits(source, const <SourceEdit>[]);
      expect(out, equals(source));
    });
  });
}
