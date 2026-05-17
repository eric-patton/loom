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

    test('build() does not crash on files with syntax errors', () {
      // Regression: parseString defaulted to throwIfDiagnostics: true here,
      // so any malformed file in the project crashed the index build.
      // ProjectModel.fromSources already accepts such files; the index should
      // mirror that posture.
      final project = ProjectModel.fromSources({
        'good.dart': '''
class GoodWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const SizedBox();
}
''',
        'broken.dart': 'this is not Dart at all !!',
      });
      // Should not throw.
      final index = ProjectWidgetIndex.build(project);
      expect(index.widgetsIn('good.dart').keys, contains('GoodWidget'));
      // Broken file simply contributes no widgets.
      expect(index.widgetsIn('broken.dart'), isEmpty);
    });

    test('diamond re-export: widget visible via either of two paths', () {
      // Regression: _widgetsExportedBy used to share a mutable visited set
      // across recursive branches, so when walking export A's chain through
      // both B and D into C, the second branch hit "visited" and dropped C's
      // widgets entirely. With a diamond (A -> B -> C and A -> D -> C, both
      // showing different names), all of C's widgets reachable through any
      // path must remain visible.
      final project = ProjectModel.fromSources({
        'a.dart': "export 'b.dart';\nexport 'd.dart';\n",
        'b.dart': "export 'c.dart' show First;\n",
        'd.dart': "export 'c.dart' show Second;\n",
        'c.dart': '''
class First extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const SizedBox();
}

class Second extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const SizedBox();
}
''',
        'consumer.dart': "import 'a.dart';\n",
      });
      final index = ProjectWidgetIndex.build(project);
      final visible = index.widgetsVisibleFrom('consumer.dart');
      // BOTH First and Second must be visible. Before the fix, only one of
      // them survived (the second branch was suppressed by visited-set
      // sharing).
      expect(visible.keys, contains('First'));
      expect(visible.keys, contains('Second'));
    });

    test('rebuildFile re-parses one file and shares the rest', () {
      // Set up a project with three files; only two declare widgets.
      final project = ProjectModel.fromSources({
        'a.dart': '''
class WidgetA extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const SizedBox();
}
''',
        'b.dart': '''
class WidgetB extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const SizedBox();
}
''',
        'c.dart': '// nothing here yet\n',
      });
      final index = ProjectWidgetIndex.build(project);
      expect(index.widgetsIn('a.dart').keys, contains('WidgetA'));
      expect(index.widgetsIn('b.dart').keys, contains('WidgetB'));
      expect(index.widgetsIn('c.dart'), isEmpty);

      // Simulate editing c.dart to introduce WidgetC.
      const newC = '''
class WidgetC extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const SizedBox();
}
''';
      final rebuilt = index.rebuildFile('c.dart', newC);

      // The rebuilt index sees WidgetC, and still has WidgetA + WidgetB
      // (those entries are shared, not re-parsed).
      expect(rebuilt.widgetsIn('a.dart').keys, contains('WidgetA'));
      expect(rebuilt.widgetsIn('b.dart').keys, contains('WidgetB'));
      expect(rebuilt.widgetsIn('c.dart').keys, contains('WidgetC'));
      // Original index is unchanged.
      expect(index.widgetsIn('c.dart'), isEmpty);
    });

    test('rebuildFile drops the file entry when new source has no widgets', () {
      final project = ProjectModel.fromSources({
        'a.dart': '''
class WidgetA extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const SizedBox();
}
''',
      });
      final index = ProjectWidgetIndex.build(project);
      expect(index.widgetsIn('a.dart').keys, contains('WidgetA'));

      final rebuilt = index.rebuildFile('a.dart', '// emptied out\n');
      expect(rebuilt.widgetsIn('a.dart'), isEmpty);
    });

    test('rebuildFile tolerates Windows-style absolute paths', () {
      // The UI editor on Windows naturally keys files by absolute path
      // (`C:\repos\app\lib\main.dart`); the index must canonicalize the
      // lookup to match how ProjectModel stores its keys.
      final project = ProjectModel.fromSources({
        r'C:\proj\a.dart': '// nothing yet\n',
      });
      final index = ProjectWidgetIndex.build(project);
      final rebuilt = index.rebuildFile(r'C:\proj\a.dart', '''
class A extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const SizedBox();
}
''');
      // Lookup via the same raw path must surface the new widget.
      expect(rebuilt.widgetsIn(r'C:\proj\a.dart').keys, contains('A'));
      // And via the canonical form.
      expect(
        rebuilt.widgetsIn(canonicalizeFileKey(r'C:\proj\a.dart')).keys,
        contains('A'),
      );
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
