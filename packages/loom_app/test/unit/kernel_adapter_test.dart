import 'package:flutter_test/flutter_test.dart';
import 'package:loom_app/src/services/kernel_adapter.dart';

void main() {
  const adapter = KernelAdapter();

  group('KernelAdapter.parseWidgetTreeFor', () {
    test('returns modeled for a simple build() returning Text', () {
      const source = '''
class Greet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Text('hi');
  }
}
''';
      final result = adapter.parseWidgetTreeFor(source: source);
      expect(result, isA<WidgetTreeParseModeled>());
      final modeled = result as WidgetTreeParseModeled;
      expect(modeled.model.root, isA<WidgetNode>());
      expect((modeled.model.root as WidgetNode).className, 'Text');
    });

    test('returns failure when no class with build() exists', () {
      const source = 'void main() {}';
      final result = adapter.parseWidgetTreeFor(source: source);
      expect(result, isA<WidgetTreeParseFailure>());
      expect(
        (result as WidgetTreeParseFailure).message,
        contains('No build() method'),
      );
    });

    test('captures cross-file widgets from projectWidgets map', () {
      const card = '''
class MyCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const SizedBox();
}
''';
      const app = '''
class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MyCard();
  }
}
''';
      final project = adapter.buildProject(<String, String>{
        'card.dart': card,
        'app.dart': app,
      });
      final index = adapter.buildWidgetIndex(project);
      final visible = index.widgetsVisibleFrom('app.dart');
      // No explicit import, so visible should be empty.
      expect(visible, isEmpty);

      // With import.
      const appWithImport = '''
import 'card.dart';
class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MyCard();
  }
}
''';
      final project2 = adapter.buildProject(<String, String>{
        'card.dart': card,
        'app.dart': appWithImport,
      });
      final index2 = adapter.buildWidgetIndex(project2);
      final visible2 = index2.widgetsVisibleFrom('app.dart');
      expect(visible2.keys, contains('MyCard'));
    });
  });

  group('KernelAdapter.applyPropertyEdit', () {
    test('replaces the literal at oldValue.span', () {
      const source = '''
class Greet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Text('hi');
  }
}
''';
      final result =
          adapter.parseWidgetTreeFor(source: source) as WidgetTreeParseModeled;
      final root = result.model.root as WidgetNode;
      final dataValue = root.properties['data']! as StringLiteralValue;
      final updated = adapter.applyPropertyEdit(
        source: source,
        oldValue: dataValue,
        newValue: StringLiteralValue(
          value: 'hello',
          usesDoubleQuotes: dataValue.usesDoubleQuotes,
          span: dataValue.span,
        ),
      );
      expect(updated, contains("Text('hello')"));
      expect(updated, isNot(contains("Text('hi')")));
    });

    test('preserves byte length outside the edit range', () {
      const source = '''
class A extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Text('x');
  }
}
''';
      final result =
          adapter.parseWidgetTreeFor(source: source) as WidgetTreeParseModeled;
      final dataValue = (result.model.root as WidgetNode).properties['data']!
          as StringLiteralValue;
      final updated = adapter.applyPropertyEdit(
        source: source,
        oldValue: dataValue,
        newValue: StringLiteralValue(
          value: 'y',
          usesDoubleQuotes: dataValue.usesDoubleQuotes,
          span: dataValue.span,
        ),
      );
      expect(updated.length, source.length);
    });
  });
}
