import 'package:loom/loom.dart';
import 'package:test/test.dart';

/// Tests for `ProjectWidgetIndex.resolveBuildTree` (added in M13.5).
/// The materializer uses this to recurse into user widgets so the canvas
/// can render Counter's actual Scaffold/Center/Text — not a placeholder.
void main() {
  group('ProjectWidgetIndex.declaringFileOf', () {
    test('returns the canonical path of the file declaring the widget', () {
      final project = ProjectModel.fromSources({
        'lib/widgets/counter.dart': '''
class Counter extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const SizedBox();
}
''',
      });
      final index = ProjectWidgetIndex.build(project);
      final declaring = index.declaringFileOf('Counter');
      expect(declaring, isNotNull);
      expect(declaring, contains('counter.dart'));
    });

    test('returns null for an unknown class', () {
      final project = ProjectModel.fromSources({
        'lib/main.dart': "void main() {}\n",
      });
      final index = ProjectWidgetIndex.build(project);
      expect(index.declaringFileOf('Nope'), isNull);
    });
  });

  group('ProjectWidgetIndex.resolveBuildTree', () {
    test('resolves a StatelessWidget declared in another file', () {
      final project = ProjectModel.fromSources({
        'lib/main.dart': '''
import 'widgets/card.dart';

class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const MyCard();
}
''',
        'lib/widgets/card.dart': '''
class MyCard extends StatelessWidget {
  const MyCard({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: Text('hi'));
}
''',
      });
      final index = ProjectWidgetIndex.build(project);
      final tree = index.resolveBuildTree(
        className: 'MyCard',
        fromFile: 'lib/main.dart',
      );
      expect(tree, isNotNull);
      final root = tree!.root as WidgetNode;
      expect(root.className, equals('Center'));
    });

    test('resolves a StatefulWidget via its State<X> class', () {
      final project = ProjectModel.fromSources({
        'lib/main.dart': '''
import 'widgets/counter.dart';

class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const Counter();
}
''',
        'lib/widgets/counter.dart': '''
class Counter extends StatefulWidget {
  const Counter({super.key});
  @override
  State<Counter> createState() => _CounterState();
}

class _CounterState extends State<Counter> {
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Text('inside'));
}
''',
      });
      final index = ProjectWidgetIndex.build(project);
      final tree = index.resolveBuildTree(
        className: 'Counter',
        fromFile: 'lib/main.dart',
      );
      expect(tree, isNotNull);
      final root = tree!.root as WidgetNode;
      expect(root.className, equals('Scaffold'));
    });

    test('resolves an intra-file widget', () {
      final project = ProjectModel.fromSources({
        'lib/main.dart': '''
class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const Inner();
}

class Inner extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(8),
        child: Text('inner'),
      );
}
''',
      });
      final index = ProjectWidgetIndex.build(project);
      final tree = index.resolveBuildTree(
        className: 'Inner',
        fromFile: 'lib/main.dart',
      );
      expect(tree, isNotNull);
      final root = tree!.root as WidgetNode;
      expect(root.className, equals('Padding'));
    });

    test('returns null when the class is not visible from the caller', () {
      final project = ProjectModel.fromSources({
        // `main.dart` does NOT import card.dart.
        'lib/main.dart': '''
class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const Text('no card');
}
''',
        'lib/widgets/card.dart': '''
class MyCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const Text('card');
}
''',
      });
      final index = ProjectWidgetIndex.build(project);
      final tree = index.resolveBuildTree(
        className: 'MyCard',
        fromFile: 'lib/main.dart',
      );
      expect(tree, isNull);
    });

    test('returns null for an entirely unknown class', () {
      final project = ProjectModel.fromSources({
        'lib/main.dart': 'void main() {}\n',
      });
      final index = ProjectWidgetIndex.build(project);
      final tree = index.resolveBuildTree(
        className: 'Nowhere',
        fromFile: 'lib/main.dart',
      );
      expect(tree, isNull);
    });
  });
}
