import 'package:loom/loom.dart';
import 'package:test/test.dart';

/// Tests for the `targetClassName` parameter on `parseWidgetTree`,
/// added in M13.5 so `ProjectWidgetIndex.resolveBuildTree` can pull a
/// specific class's build body out of a file declaring several classes.
void main() {
  const counterAppSource = r'''
import 'package:flutter/material.dart';

class CounterApp extends StatelessWidget {
  const CounterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: Text('outer'));
  }
}

class Counter extends StatefulWidget {
  const Counter({super.key});

  @override
  State<Counter> createState() => _CounterState();
}

class _CounterState extends State<Counter> {
  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Text('inner'));
  }
}
''';

  group('parseWidgetTree(targetClassName: ...)', () {
    test('null target falls back to first class with build()', () {
      final model = parseWidgetTree(counterAppSource);
      final root = model.root as WidgetNode;
      expect(root.className, equals('MaterialApp'));
    });

    test('targets a StatelessWidget by name', () {
      final model = parseWidgetTree(
        counterAppSource,
        targetClassName: 'CounterApp',
      );
      final root = model.root as WidgetNode;
      expect(root.className, equals('MaterialApp'));
    });

    test('targets a State<X> class by name', () {
      final model = parseWidgetTree(
        counterAppSource,
        targetClassName: '_CounterState',
      );
      final root = model.root as WidgetNode;
      expect(root.className, equals('Scaffold'));
    });

    test('throws when target class is missing', () {
      expect(
        () => parseWidgetTree(
          counterAppSource,
          targetClassName: 'DoesNotExist',
        ),
        throwsA(
          isA<ParseException>().having(
            (e) => e.message,
            'message',
            contains('DoesNotExist'),
          ),
        ),
      );
    });

    test('throws when target class has no build()', () {
      // `Counter` has only `createState`, not `build`.
      expect(
        () => parseWidgetTree(
          counterAppSource,
          targetClassName: 'Counter',
        ),
        throwsA(
          isA<ParseException>().having(
            (e) => e.message,
            'message',
            contains('Counter'),
          ),
        ),
      );
    });
  });
}
