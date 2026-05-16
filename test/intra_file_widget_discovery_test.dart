import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:loom/loom.dart';
import 'package:test/test.dart';

void main() {
  group('discoverIntraFileWidgets', () {
    test('finds class extending StatelessWidget', () {
      const source = '''
import 'package:flutter/widgets.dart';

class MyBox extends StatelessWidget {
  const MyBox({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox();
}
''';
      final unit = parseString(content: source).unit;
      final discovered = discoverIntraFileWidgets(unit);
      expect(discovered.keys, contains('MyBox'));
    });

    test('finds class extending StatefulWidget', () {
      const source = '''
import 'package:flutter/widgets.dart';

class MyPage extends StatefulWidget {
  const MyPage({super.key});

  @override
  State<MyPage> createState() => _MyPageState();
}

class _MyPageState extends State<MyPage> {
  @override
  Widget build(BuildContext context) => const SizedBox();
}
''';
      final unit = parseString(content: source).unit;
      final discovered = discoverIntraFileWidgets(unit);
      // Public widget should be discovered.
      expect(discovered.keys, contains('MyPage'));
      // State<MyPage> does NOT end in "Widget" — exclude it.
      expect(discovered.keys, isNot(contains('_MyPageState')));
    });

    test('excludes classes with no extends clause', () {
      const source = '''
class PlainClass {
  final int value;
  PlainClass(this.value);
}
''';
      final unit = parseString(content: source).unit;
      expect(discoverIntraFileWidgets(unit), isEmpty);
    });

    test('excludes classes extending non-Widget bases', () {
      const source = '''
class MyList extends ListBase<int> {}
class MyException implements Exception {}
class MyService extends BaseService {}
''';
      final unit = parseString(content: source).unit;
      expect(discoverIntraFileWidgets(unit), isEmpty);
    });

    test(
        'recognizes third-party widget conventions (HookWidget, ConsumerWidget)',
        () {
      const source = '''
class HookishView extends HookWidget {
  @override
  Widget build(BuildContext context) => const SizedBox();
}

class RiverpodView extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) => const SizedBox();
}

class HybridView extends ConsumerStatefulWidget {
  @override
  ConsumerState<HybridView> createState() => _HybridViewState();
}
''';
      final unit = parseString(content: source).unit;
      final discovered = discoverIntraFileWidgets(unit);
      expect(discovered.keys,
          containsAll(['HookishView', 'RiverpodView', 'HybridView']));
    });

    test('returned WidgetSpec is empty (no slots, no positionals)', () {
      const source = '''
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const SizedBox();
}
''';
      final unit = parseString(content: source).unit;
      final discovered = discoverIntraFileWidgets(unit);
      final spec = discovered['MyWidget']!;
      expect(spec.childSlots, isEmpty);
      expect(spec.positionalToProperty, isEmpty);
    });

    test('framework catalog wins over local catalog on name collision', () {
      // Hypothetical: a project defines its own `Padding` extending
      // StatelessWidget. The framework `Padding` from the catalog should
      // still take precedence (it has known child slots).
      // App is FIRST so its build is the one parseWidgetTree models.
      const source = '''
class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(child: const SizedBox());
  }
}

class Padding extends StatelessWidget {
  const Padding({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}
''';
      final model = parseWidgetTree(source);
      final root = model.root as WidgetNode;
      expect(root.className, equals('Padding'));
      // Framework catalog has Padding with single `child` slot —
      // so SizedBox should land in the slot, not as opaque property.
      expect(root.childSlots.containsKey('child'), isTrue);
    });
  });

  group('parseWidgetTree with intra-file discovery', () {
    test('user-defined widget at root becomes WidgetNode (was OpaqueNode)', () {
      // HomePage is FIRST so its build is parsed; it returns _Body().
      const source = '''
class HomePage extends StatelessWidget {
  const HomePage();
  @override
  Widget build(BuildContext context) {
    return _Body();
  }
}

class _Body extends StatelessWidget {
  const _Body();
  @override
  Widget build(BuildContext context) => const SizedBox();
}
''';
      final model = parseWidgetTree(source);
      // Before this milestone: root would have been OpaqueNode.
      // After: root is WidgetNode(_Body) with no children.
      expect(model.root, isA<WidgetNode>());
      final root = model.root as WidgetNode;
      expect(root.className, equals('_Body'));
    });

    test('user-defined widget nested inside framework widget is WidgetNode',
        () {
      // App FIRST: its build is parsed; nested _Card references should
      // classify as WidgetNode (not OpaqueNode) thanks to discovery.
      const source = '''
class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _Card(),
        _Card(),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card();
  @override
  Widget build(BuildContext context) => const SizedBox();
}
''';
      final model = parseWidgetTree(source);
      final root = model.root as WidgetNode;
      expect(root.className, equals('Column'));
      final children = root.childSlots['children']!;
      expect(children, hasLength(2));
      expect(children[0], isA<WidgetNode>());
      expect((children[0] as WidgetNode).className, equals('_Card'));
      expect((children[1] as WidgetNode).className, equals('_Card'));
    });

    test(
        'user-defined widget args land as opaque properties (no slot inference)',
        () {
      // App FIRST: parser models App.build = MyCard(child: ..., title: ...).
      const source = '''
class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MyCard(child: const SizedBox(), title: 'hello');
  }
}

class MyCard extends StatelessWidget {
  const MyCard({super.key, required this.child, required this.title});
  final Widget child;
  final String title;
  @override
  Widget build(BuildContext context) => child;
}
''';
      final model = parseWidgetTree(source);
      final root = model.root as WidgetNode;
      expect(root.className, equals('MyCard'));
      // Empty WidgetSpec means no child slots → both args become properties.
      expect(root.childSlots, isEmpty);
      expect(root.properties.keys, containsAll(['child', 'title']));
      // The child: arg becomes an opaque property (since not a known slot).
      expect(root.properties['child'], isA<OpaquePropertyValue>());
      // title: is a literal string, modeled as StringLiteralValue.
      expect(root.properties['title'], isA<StringLiteralValue>());
    });

    test('class without extends clause is not registered', () {
      const source = '''
class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return PlainHelper();
  }
}

class PlainHelper {
  const PlainHelper();
}
''';
      final model = parseWidgetTree(source);
      // PlainHelper has no extends clause — NOT registered. Falls to opaque.
      expect(model.root, isA<OpaqueNode>());
    });

    test('round-trip invariant holds for user-defined widget at root', () {
      const source = '''
class _Inner extends StatelessWidget {
  const _Inner();
  @override
  Widget build(BuildContext context) => const SizedBox();
}

class _Outer extends StatelessWidget {
  const _Outer();
  @override
  Widget build(BuildContext context) {
    return _Inner();
  }
}
''';
      // Idempotence: applying zero edits leaves source byte-identical.
      final out = applySourceEdits(source, const <SourceEdit>[]);
      expect(out, equals(source));
      // Parse must succeed.
      expect(() => parseWidgetTree(source), returnsNormally);
    });
  });
}
