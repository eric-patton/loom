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

    test('slot inference: `Widget child` becomes single slot', () {
      const source = '''
class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MyCard(child: const SizedBox());
  }
}

class MyCard extends StatelessWidget {
  const MyCard({required Widget child});
  @override
  Widget build(BuildContext context) => const SizedBox();
}
''';
      final model = parseWidgetTree(source);
      final root = model.root as WidgetNode;
      expect(root.className, equals('MyCard'));
      expect(root.childSlots.containsKey('child'), isTrue);
      expect(root.childSlots['child'], hasLength(1));
      expect(root.childSlots['child']!.first, isA<WidgetNode>());
      expect((root.childSlots['child']!.first as WidgetNode).className,
          equals('SizedBox'));
    });

    test('slot inference: `this.child` resolves through field declaration',
        () {
      const source = '''
class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MyCard(child: const SizedBox());
  }
}

class MyCard extends StatelessWidget {
  const MyCard({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}
''';
      final model = parseWidgetTree(source);
      final root = model.root as WidgetNode;
      expect(root.className, equals('MyCard'));
      expect(root.childSlots.containsKey('child'), isTrue);
      expect((root.childSlots['child']!.first as WidgetNode).className,
          equals('SizedBox'));
    });

    test('slot inference: `List<Widget> children` becomes list slot', () {
      const source = '''
class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MyRow(
      children: [
        const SizedBox(),
        const Padding(padding: EdgeInsets.all(4)),
      ],
    );
  }
}

class MyRow extends StatelessWidget {
  const MyRow({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Row(children: children);
}
''';
      final model = parseWidgetTree(source);
      final root = model.root as WidgetNode;
      expect(root.className, equals('MyRow'));
      expect(root.childSlots.containsKey('children'), isTrue);
      expect(root.childSlots['children'], hasLength(2));
      final first = root.childSlots['children']!.first as WidgetNode;
      expect(first.className, equals('SizedBox'));
    });

    test('slot inference: nullable `Widget? child` still becomes a slot', () {
      const source = '''
class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MyCard(child: const SizedBox());
  }
}

class MyCard extends StatelessWidget {
  const MyCard({this.child});
  final Widget? child;
  @override
  Widget build(BuildContext context) => child ?? const SizedBox();
}
''';
      final model = parseWidgetTree(source);
      final root = model.root as WidgetNode;
      expect(root.childSlots.containsKey('child'), isTrue);
    });

    test('slot inference: function-typed param is NOT classified as a slot',
        () {
      // Common builder pattern. `Widget Function(BuildContext)` is NOT a
      // child slot — calling it requires a BuildContext at runtime.
      const source = '''
class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MyBuilder(builder: (ctx) => const SizedBox());
  }
}

class MyBuilder extends StatelessWidget {
  const MyBuilder({required this.builder});
  final Widget Function(BuildContext) builder;
  @override
  Widget build(BuildContext context) => builder(context);
}
''';
      final model = parseWidgetTree(source);
      final root = model.root as WidgetNode;
      expect(root.className, equals('MyBuilder'));
      // The builder param should NOT be a child slot.
      expect(root.childSlots.containsKey('builder'), isFalse);
      // It becomes an opaque property (the function literal).
      expect(root.properties.containsKey('builder'), isTrue);
      expect(root.properties['builder'], isA<OpaquePropertyValue>());
    });

    test('slot inference: typedef-named function type is NOT a slot', () {
      // We can't resolve typedefs without semantic analysis. The conservative
      // path: `WidgetBuilder` (typedef for `Widget Function(BuildContext)`)
      // doesn't match `Widget` exactly, so it's NOT classified as a slot.
      // This is intentional — false-positive on a builder would break edits.
      const source = '''
class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MyView(builder: (ctx) => const SizedBox());
  }
}

class MyView extends StatelessWidget {
  const MyView({required this.builder});
  final WidgetBuilder builder;
  @override
  Widget build(BuildContext context) => builder(context);
}
''';
      final model = parseWidgetTree(source);
      final root = model.root as WidgetNode;
      expect(root.childSlots.containsKey('builder'), isFalse);
    });

    test('slot inference: mixed slot + property params handled correctly', () {
      const source = '''
class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MyCard(
      title: 'hello',
      child: const SizedBox(),
      enabled: true,
    );
  }
}

class MyCard extends StatelessWidget {
  const MyCard({required this.title, required this.child, this.enabled = true});
  final String title;
  final Widget child;
  final bool enabled;
  @override
  Widget build(BuildContext context) => child;
}
''';
      final model = parseWidgetTree(source);
      final root = model.root as WidgetNode;
      expect(root.childSlots.containsKey('child'), isTrue);
      expect(root.childSlots.containsKey('title'), isFalse);
      expect(root.childSlots.containsKey('enabled'), isFalse);
      expect(root.properties['title'], isA<StringLiteralValue>());
      expect(root.properties['enabled'], isA<BoolLiteralValue>());
    });

    test('slot inference: prefers unnamed constructor over named ones', () {
      // The unnamed `MyCard(...)` constructor is what `MyCard(...)` calls
      // resolve to. Named alternatives (`MyCard.empty()`) are inert here.
      const source = '''
class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MyCard(child: const SizedBox());
  }
}

class MyCard extends StatelessWidget {
  const MyCard.empty() : child = const SizedBox();
  const MyCard({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}
''';
      final model = parseWidgetTree(source);
      final root = model.root as WidgetNode;
      expect(root.childSlots.containsKey('child'), isTrue);
    });

    test(
        'multi-reference defense counts helpers inside user-widget inferred slots',
        () {
      // Regression: when slot inference gives a user widget a `child:` slot,
      // a helper referenced inside that slot AND at another position counts
      // as multi-reference — the counter must see both. Without this, the
      // counter would treat the helper as safe → both call sites become
      // MethodReferenceNode → in-memory edits diverge from reparsed source.
      const source = '''
class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      MyCard(child: _helper()),
      _helper(),
    ]);
  }

  Widget _helper() => const SizedBox();
}

class MyCard extends StatelessWidget {
  const MyCard({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}
''';
      final model = parseWidgetTree(source);
      final root = model.root as WidgetNode;
      final children = root.childSlots['children']!;
      // Two call sites for _helper. Counter must mark it multi-ref → both
      // sites become OpaqueNode, not MethodReferenceNode.
      final myCard = children[0] as WidgetNode;
      final helperInSlot = myCard.childSlots['child']!.first;
      final helperDirect = children[1];
      expect(helperInSlot, isA<OpaqueNode>(),
          reason: 'helper inside user-widget slot must be opaque (multi-ref)');
      expect(helperDirect, isA<OpaqueNode>(),
          reason: 'helper at direct position must be opaque (multi-ref)');
    });

    test('single helper reference inside user-widget slot resolves cleanly',
        () {
      // Counterpart: when a helper is referenced exactly once (inside a
      // user-widget slot), the visitor SHOULD resolve it to a
      // MethodReferenceNode. Verifies the recursion reaches inferred slots.
      const source = '''
class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MyCard(child: _helper());
  }

  Widget _helper() => const SizedBox();
}

class MyCard extends StatelessWidget {
  const MyCard({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}
''';
      final model = parseWidgetTree(source);
      final root = model.root as WidgetNode;
      final helperRef = root.childSlots['child']!.first;
      expect(helperRef, isA<MethodReferenceNode>());
      expect((helperRef as MethodReferenceNode).methodName, equals('_helper'));
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
