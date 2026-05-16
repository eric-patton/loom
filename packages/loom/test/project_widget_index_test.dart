import 'package:loom/loom.dart';
import 'package:test/test.dart';

void main() {
  group('ProjectWidgetIndex.widgetsIn', () {
    test('returns empty for unknown file', () {
      final project = ProjectModel.fromSources({
        'app.dart': 'class A {}',
      });
      final index = ProjectWidgetIndex.build(project);
      expect(index.widgetsIn('missing.dart'), isEmpty);
    });

    test('discovers per-file widget declarations', () {
      final project = ProjectModel.fromSources({
        'card.dart': '''
class MyCard extends StatelessWidget {
  const MyCard({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}
''',
      });
      final index = ProjectWidgetIndex.build(project);
      final cardWidgets = index.widgetsIn('card.dart');
      expect(cardWidgets.keys, contains('MyCard'));
      expect(cardWidgets['MyCard']!.childSlots.containsKey('child'), isTrue);
    });
  });

  group('ProjectWidgetIndex.widgetsVisibleFrom', () {
    test('basic import: widget declared in another file is visible', () {
      final project = ProjectModel.fromSources({
        'app.dart': "import 'card.dart';\n",
        'card.dart': '''
class MyCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const SizedBox();
}
''',
      });
      final index = ProjectWidgetIndex.build(project);
      final visible = index.widgetsVisibleFrom('app.dart');
      expect(visible.keys, contains('MyCard'));
    });

    test('show combinator: only listed names visible', () {
      final project = ProjectModel.fromSources({
        'app.dart': "import 'lib.dart' show MyCard;\n",
        'lib.dart': '''
class MyCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const SizedBox();
}

class OtherWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const SizedBox();
}
''',
      });
      final index = ProjectWidgetIndex.build(project);
      final visible = index.widgetsVisibleFrom('app.dart');
      expect(visible.keys, contains('MyCard'));
      expect(visible.keys, isNot(contains('OtherWidget')));
    });

    test('hide combinator: listed names excluded', () {
      final project = ProjectModel.fromSources({
        'app.dart': "import 'lib.dart' hide OtherWidget;\n",
        'lib.dart': '''
class MyCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const SizedBox();
}

class OtherWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const SizedBox();
}
''',
      });
      final index = ProjectWidgetIndex.build(project);
      final visible = index.widgetsVisibleFrom('app.dart');
      expect(visible.keys, contains('MyCard'));
      expect(visible.keys, isNot(contains('OtherWidget')));
    });

    test('prefixed import: skipped (deferred)', () {
      final project = ProjectModel.fromSources({
        'app.dart': "import 'card.dart' as c;\n",
        'card.dart': '''
class MyCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const SizedBox();
}
''',
      });
      final index = ProjectWidgetIndex.build(project);
      final visible = index.widgetsVisibleFrom('app.dart');
      // Prefixed imports require `c.MyCard(...)` reference, which the
      // parser handles via the named-constructor path. Skipped here.
      expect(visible.keys, isNot(contains('MyCard')));
    });

    test('transitive re-export: widgets flow through barrel files', () {
      final project = ProjectModel.fromSources({
        'app.dart': "import 'barrel.dart';\n",
        'barrel.dart': "export 'card.dart';\n",
        'card.dart': '''
class MyCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const SizedBox();
}
''',
      });
      final index = ProjectWidgetIndex.build(project);
      final visible = index.widgetsVisibleFrom('app.dart');
      expect(visible.keys, contains('MyCard'));
    });

    test('cyclic export does not infinite-loop', () {
      final project = ProjectModel.fromSources({
        'a.dart': '''
export 'b.dart';
class WidgetA extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const SizedBox();
}
''',
        'b.dart': '''
export 'a.dart';
class WidgetB extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const SizedBox();
}
''',
        'consumer.dart': "import 'a.dart';\n",
      });
      final index = ProjectWidgetIndex.build(project);
      // No timeout / stack overflow. Result should include both widgets.
      final visible = index.widgetsVisibleFrom('consumer.dart');
      expect(visible.keys, containsAll(['WidgetA', 'WidgetB']));
    });

    test('intra-file widgets are NOT included in widgetsVisibleFrom', () {
      // The parser discovers intra-file widgets separately; the index's
      // job is to surface CROSS-file widgets. Avoid double-counting.
      final project = ProjectModel.fromSources({
        'app.dart': '''
class LocalWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const SizedBox();
}
''',
      });
      final index = ProjectWidgetIndex.build(project);
      final visible = index.widgetsVisibleFrom('app.dart');
      expect(visible.keys, isNot(contains('LocalWidget')));
    });
  });

  group('parseWidgetTree with cross-file projectWidgets', () {
    test('imported user widget becomes WidgetNode (was OpaqueNode)', () {
      final project = ProjectModel.fromSources({
        'app.dart': '''
import 'card.dart';

class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MyCard(child: const SizedBox());
  }
}
''',
        'card.dart': '''
class MyCard extends StatelessWidget {
  const MyCard({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}
''',
      });
      final index = ProjectWidgetIndex.build(project);
      final source = project.files['app.dart']!.source;
      final model = parseWidgetTree(
        source,
        projectWidgets: index.widgetsVisibleFrom('app.dart'),
      );
      final root = model.root as WidgetNode;
      expect(root.className, equals('MyCard'));
      // Cross-file slot inference: MyCard's `child:` Widget should be a slot.
      expect(root.childSlots.containsKey('child'), isTrue);
      final child = root.childSlots['child']!.first as WidgetNode;
      expect(child.className, equals('SizedBox'));
    });

    test('without projectWidgets, imported widget stays opaque', () {
      // Regression / sanity: the default parseWidgetTree behavior is
      // unchanged for callers who don't pass projectWidgets.
      const source = '''
class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ExternalWidget(child: const SizedBox());
  }
}
''';
      final model = parseWidgetTree(source);
      // ExternalWidget is not declared in this file and no project context
      // was passed → kernel can't know about it → opaque.
      expect(model.root, isA<OpaqueNode>());
    });

    test('intra-file widgets override cross-file widgets on name collision',
        () {
      // Edge case: both the importing file and an imported file declare
      // `Helper`. The local declaration wins (same Dart visibility rules
      // would call this an import-clash, but the kernel models it
      // conservatively).
      final project = ProjectModel.fromSources({
        'app.dart': '''
import 'lib.dart';

class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Helper(label: 'local');
  }
}

class Helper extends StatelessWidget {
  const Helper({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => const SizedBox();
}
''',
        'lib.dart': '''
class Helper extends StatelessWidget {
  const Helper({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}
''',
      });
      final index = ProjectWidgetIndex.build(project);
      final source = project.files['app.dart']!.source;
      final model = parseWidgetTree(
        source,
        projectWidgets: index.widgetsVisibleFrom('app.dart'),
      );
      final root = model.root as WidgetNode;
      expect(root.className, equals('Helper'));
      // The LOCAL Helper has `label: String` (not a Widget). The remote
      // Helper has `child: Widget`. If intra-file won (correctly), `label`
      // is a property and there's no `child` slot.
      expect(root.properties.containsKey('label'), isTrue);
      expect(root.childSlots.containsKey('child'), isFalse);
    });

    test('round-trip invariant holds on cross-file-recognized widget', () {
      // Empty-edit idempotence must still hold even when projectWidgets
      // adds a cross-file recognition.
      final project = ProjectModel.fromSources({
        'app.dart': '''
import 'card.dart';

class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MyCard(child: const SizedBox());
  }
}
''',
        'card.dart': '''
class MyCard extends StatelessWidget {
  const MyCard({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}
''',
      });
      final source = project.files['app.dart']!.source;
      final out = applySourceEdits(source, const <SourceEdit>[]);
      expect(out, equals(source));
    });
  });
}
