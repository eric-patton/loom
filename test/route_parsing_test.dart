import 'dart:io';

import 'package:loom/loom.dart';
import 'package:test/test.dart';

void main() {
  group('parseRouteTree on route_simple.dart', () {
    late String source;
    late RouteTreeModel model;
    late RouteNode root;

    setUpAll(() {
      source = File('test/fixtures/route_simple.dart').readAsStringSync();
      model = parseRouteTree(source);
      root = model.root as RouteNode;
    });

    test('root is GoRouter', () {
      expect(root.className, equals('GoRouter'));
    });

    test('no diagnostics', () {
      expect(model.diagnostics, isEmpty);
    });

    test('initialLocation property captured as string literal', () {
      final initial = root.properties['initialLocation'];
      if (initial is! StringLiteralValue) {
        fail('expected StringLiteralValue, got ${initial.runtimeType}');
      }
      expect(initial.value, equals('/'));
    });

    test('routes slot has two GoRoutes', () {
      final routes = root.childSlots['routes'];
      expect(routes, hasLength(2));
      for (final route in routes!) {
        expect(route, isA<RouteNode>());
        expect((route as RouteNode).className, equals('GoRoute'));
      }
    });

    test('first GoRoute has path "/"', () {
      final routes = root.childSlots['routes']!;
      final first = routes.first as RouteNode;
      final path = first.properties['path'];
      if (path is! StringLiteralValue) {
        fail('expected StringLiteralValue for path');
      }
      expect(path.value, equals('/'));
    });

    test('routes slot has list-shaped style with trailing comma', () {
      final style = root.childSlotStyles['routes'];
      expect(style, isNotNull);
      expect(style!.hasTrailingComma, isTrue);
      expect(style.isMultiLine, isTrue);
    });

    test('every node has a valid SourceSpan', () {
      void check(RouteTreeNode node) {
        expect(node.sourceSpan.length, greaterThan(0));
        expect(node.sourceSpan.end, lessThanOrEqualTo(source.length));
        if (node is RouteNode) {
          for (final slot in node.childSlots.values) {
            for (final child in slot) {
              check(child);
            }
          }
        }
      }

      check(root);
    });
  });

  group('parseRouteTree on route_nested.dart', () {
    late RouteTreeModel model;
    late RouteNode root;

    setUpAll(() {
      final source = File('test/fixtures/route_nested.dart').readAsStringSync();
      model = parseRouteTree(source);
      root = model.root as RouteNode;
    });

    test('parent route has two children', () {
      final routes = root.childSlots['routes']!;
      final parent = routes.first as RouteNode;
      expect(parent.className, equals('GoRoute'));

      final nestedRoutes = parent.childSlots['routes'];
      expect(nestedRoutes, hasLength(2));
      for (final r in nestedRoutes!) {
        expect((r as RouteNode).className, equals('GoRoute'));
      }
    });

    test('nested route paths captured', () {
      final routes = root.childSlots['routes']!;
      final parent = routes.first as RouteNode;
      final nested = parent.childSlots['routes']!;

      final first = nested[0] as RouteNode;
      expect((first.properties['path'] as StringLiteralValue).value,
          equals('details'));

      final second = nested[1] as RouteNode;
      expect((second.properties['path'] as StringLiteralValue).value,
          equals('settings'));
    });
  });

  group('parseRouteTree on route_shell.dart', () {
    late RouteTreeModel model;
    late RouteNode root;

    setUpAll(() {
      final source = File('test/fixtures/route_shell.dart').readAsStringSync();
      model = parseRouteTree(source);
      root = model.root as RouteNode;
    });

    test('ShellRoute is captured as a RouteNode', () {
      final routes = root.childSlots['routes']!;
      final shell = routes.first as RouteNode;
      expect(shell.className, equals('ShellRoute'));
    });

    test('ShellRoute children are GoRoutes', () {
      final routes = root.childSlots['routes']!;
      final shell = routes.first as RouteNode;
      final shellRoutes = shell.childSlots['routes'];
      expect(shellRoutes, hasLength(2));
      for (final r in shellRoutes!) {
        expect((r as RouteNode).className, equals('GoRoute'));
      }
    });
  });

  group('parseRouteTree on route_with_helper.dart', () {
    late RouteTreeModel model;
    late RouteNode root;

    setUpAll(() {
      final source =
          File('test/fixtures/route_with_helper.dart').readAsStringSync();
      model = parseRouteTree(source);
      root = model.root as RouteNode;
    });

    test('class-method fallback locates GoRouter', () {
      expect(root.className, equals('GoRouter'));
    });

    test('helper call resolves to RouteMethodReferenceNode', () {
      final routes = root.childSlots['routes']!;
      expect(routes.first, isA<RouteMethodReferenceNode>());

      final ref = routes.first as RouteMethodReferenceNode;
      expect(ref.methodName, equals('_homeRoute'));
      expect(ref.body, isA<RouteNode>());
      final body = ref.body as RouteNode;
      expect(body.className, equals('GoRoute'));
      expect((body.properties['path'] as StringLiteralValue).value,
          equals('/home'));
    });
  });

  group('parseRouteTree rejection', () {
    test('throws on a widget file', () {
      final source =
          File('test/fixtures/simple_widget.dart').readAsStringSync();
      expect(() => parseRouteTree(source), throwsA(isA<ParseException>()));
    });
  });
}
