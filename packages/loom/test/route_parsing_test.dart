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
      void check(ModelNode node) {
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

    test('helper call resolves to MethodReferenceNode', () {
      final routes = root.childSlots['routes']!;
      expect(routes.first, isA<MethodReferenceNode>());

      final ref = routes.first as MethodReferenceNode;
      expect(ref.methodName, equals('_homeRoute'));
      expect(ref.body, isA<RouteNode>());
      final body = ref.body as RouteNode;
      expect(body.className, equals('GoRoute'));
      expect((body.properties['path'] as StringLiteralValue).value,
          equals('/home'));
    });
  });

  group('parseRouteTree on real_world_go_router_main.dart', () {
    // Source: flutter/packages @ 0ffbde8f622b8dc61e4608483dc4f80f7fab027b,
    // packages/go_router/example/lib/main.dart. Canonical go_router app
    // example with a top-level `final GoRouter _router = GoRouter(...)`,
    // one nested route, and `builder:` function literals on every GoRoute.
    late RouteTreeModel model;
    late RouteNode root;

    setUpAll(() {
      final source = File('test/fixtures/real_world_go_router_main.dart')
          .readAsStringSync();
      model = parseRouteTree(source);
      root = model.root as RouteNode;
    });

    test('parses with no diagnostics', () {
      expect(model.diagnostics, isEmpty);
    });

    test('root is GoRouter with one top-level route', () {
      expect(root.className, equals('GoRouter'));
      final routes = root.childSlots['routes'];
      expect(routes, hasLength(1));
    });

    test('top route has path "/" and one nested route', () {
      final top = root.childSlots['routes']!.first as RouteNode;
      expect(top.className, equals('GoRoute'));
      expect((top.properties['path'] as StringLiteralValue).value, equals('/'));

      final nested = top.childSlots['routes'];
      expect(nested, hasLength(1));
      final detailRoute = nested!.first as RouteNode;
      expect((detailRoute.properties['path'] as StringLiteralValue).value,
          equals('details'));
    });

    test('builder properties land as opaque (function literals)', () {
      final top = root.childSlots['routes']!.first as RouteNode;
      expect(top.properties['builder'], isA<OpaquePropertyValue>());

      final nested = top.childSlots['routes']!.first as RouteNode;
      expect(nested.properties['builder'], isA<OpaquePropertyValue>());
    });

    test('typed list literal <RouteBase>[...] is parsed as list slot', () {
      // The list literal has a type annotation; the visitor must still
      // recognize it as a ListLiteral and capture per-slot list style.
      final style = root.childSlotStyles['routes'];
      expect(style, isNotNull);
      expect(style!.hasTrailingComma, isTrue);
      expect(style.isMultiLine, isTrue);
    });
  });

  group('parseRouteTree on real_world_go_router_named_routes.dart', () {
    // Source: flutter/packages @ 0ffbde8f622b8dc61e4608483dc4f80f7fab027b,
    // packages/go_router/example/lib/named_routes.dart. Exercises the
    // M6.0.1 class-field-initializer entry-point path:
    // `late final GoRouter _router = GoRouter(...)` inside a class.
    late RouteTreeModel model;
    late RouteNode root;

    setUpAll(() {
      final source =
          File('test/fixtures/real_world_go_router_named_routes.dart')
              .readAsStringSync();
      model = parseRouteTree(source);
      root = model.root as RouteNode;
    });

    test('class-field initializer is detected as the route root', () {
      expect(root.className, equals('GoRouter'));
    });

    test('triple-nested routes resolve', () {
      final top = root.childSlots['routes']!.first as RouteNode;
      final family = (top.childSlots['routes']!.first as RouteNode);
      final person = (family.childSlots['routes']!.first as RouteNode);
      expect(
          (top.properties['name'] as StringLiteralValue).value, equals('home'));
      expect((family.properties['name'] as StringLiteralValue).value,
          equals('family'));
      expect((person.properties['name'] as StringLiteralValue).value,
          equals('person'));
      expect((person.properties['path'] as StringLiteralValue).value,
          equals('person/:pid'));
    });

    test('debugLogDiagnostics: true captured as bool literal', () {
      final debug = root.properties['debugLogDiagnostics'];
      expect(debug, isA<BoolLiteralValue>());
      expect((debug! as BoolLiteralValue).value, isTrue);
    });
  });

  group('parseRouteTree rejection', () {
    test('throws on a widget file', () {
      final source =
          File('test/fixtures/simple_widget.dart').readAsStringSync();
      expect(() => parseRouteTree(source), throwsA(isA<ParseException>()));
    });

    test('prefixed-import root falls back rather than mismatching', () {
      // Regression: _isRouteRoot used to say "yes, this is a route root"
      // for `const grouter.GoRouter(...)`, but the visitor sees className
      // = 'grouter' and produces OpaqueNode. The mismatch left
      // RouteTreeModel.root as OpaqueNode even though the kernel had
      // committed to "this file has a route tree." Now _isRouteRoot
      // returns false on prefixed InstanceCreation; the parser keeps
      // looking and (in this single-root example) throws.
      const source = '''
import 'package:go_router/go_router.dart' as grouter;
final router = const grouter.GoRouter(initialLocation: '/');
''';
      expect(() => parseRouteTree(source), throwsA(isA<ParseException>()));
    });

    test('sibling route-root method is not stashed as a helper', () {
      // Regression: when a class had two methods both returning route
      // roots, the second was incorrectly added to classMethods. A
      // zero-arg call to it from the first would resolve as a
      // MethodReferenceNode pointing at the wrong subtree. Now it isn't
      // registered at all.
      const source = '''
class Routers {
  GoRouter buildPrimary() => GoRouter(initialLocation: '/', routes: [
    GoRoute(path: '/a', builder: (c, s) => null),
  ]);
  GoRouter buildBackup() => GoRouter(initialLocation: '/x', routes: [
    GoRoute(path: '/b', builder: (c, s) => null),
  ]);
}
''';
      final model = parseRouteTree(source);
      // Primary becomes the root; backup is NOT a helper for primary,
      // so primary's body has no MethodReferenceNode to backup.
      final root = model.root as RouteNode;
      expect(root.className, equals('GoRouter'));
      final routes = root.childSlots['routes']!;
      expect(routes, hasLength(1));
      final first = routes.first as RouteNode;
      expect(first.className, equals('GoRoute'));
    });
  });

  // ----------------------------------------------------------------
  // RouteTreeNavigation — node_path API extended to route trees.
  // ----------------------------------------------------------------
  group('RouteTreeNavigation — nodeAt / withProperty / walk', () {
    late RouteTreeModel model;

    setUp(() {
      const source = '''
final router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (c, s) => null),
    GoRoute(path: '/about', builder: (c, s) => null),
  ],
);
''';
      model = parseRouteTree(source);
    });

    test('nodeAt(empty) returns the root', () {
      final got = model.nodeAt(const <NodePathSegment>[]);
      expect(got, equals(model.root));
      expect(got, isA<RouteNode>());
      expect((got! as RouteNode).className, equals('GoRouter'));
    });

    test('nodeAt(routes, 1) returns the second GoRoute', () {
      final got = model.nodeAt(const [(slot: 'routes', index: 1)]);
      expect(got, isA<RouteNode>());
      final route = got! as RouteNode;
      expect(route.className, equals('GoRoute'));
      final path = route.properties['path'] as StringLiteralValue;
      expect(path.value, equals('/about'));
    });

    test('nodeAt with bad slot returns null', () {
      final got = model.nodeAt(const [(slot: 'nope', index: 0)]);
      expect(got, isNull);
    });

    test('withProperty updates a RouteNode property and preserves the type',
        () {
      final updated = model.withProperty(
        const <NodePathSegment>[],
        'initialLocation',
        const StringLiteralValue(
          value: '/home',
          span: SourceSpan(offset: 0, length: 0),
        ),
      );
      expect(updated.root, isA<RouteNode>(),
          reason: 'rebuilt root must stay a RouteNode, not a WidgetNode');
      final newRoot = updated.root as RouteNode;
      final newLoc =
          newRoot.properties['initialLocation'] as StringLiteralValue;
      expect(newLoc.value, equals('/home'));
      // Other properties left alone.
      expect(newRoot.childSlots['routes']!.length, equals(2));
      // namedConstructor / styleHints preserved.
      expect(newRoot.namedConstructor,
          equals((model.root as RouteNode).namedConstructor));
      expect(newRoot.styleHints, equals((model.root as RouteNode).styleHints));
    });

    test('withProperty descends into a child RouteNode', () {
      final updated = model.withProperty(
        const [(slot: 'routes', index: 0)],
        'path',
        const StringLiteralValue(
          value: '/index',
          span: SourceSpan(offset: 0, length: 0),
        ),
      );
      final first = updated.nodeAt(const [(slot: 'routes', index: 0)]);
      expect(first, isA<RouteNode>());
      final path =
          (first! as RouteNode).properties['path'] as StringLiteralValue;
      expect(path.value, equals('/index'));
    });

    test('insertChild adds to a list slot', () {
      final newRoute = RouteNode(
        className: 'GoRoute',
        properties: const {
          'path': StringLiteralValue(
            value: '/inserted',
            span: SourceSpan(offset: 0, length: 0),
          ),
        },
        childSlots: const {},
        sourceSpan: const SourceSpan(offset: 0, length: 0),
        styleHints: const StyleHints(),
      );
      final updated = model.insertChild(
        const <NodePathSegment>[],
        'routes',
        1,
        newRoute,
      );
      final routes = (updated.root as RouteNode).childSlots['routes']!;
      expect(routes, hasLength(3));
      expect((routes[1] as RouteNode).properties['path'],
          isA<StringLiteralValue>());
    });

    test('removeChild removes from a list slot', () {
      final updated = model.removeChild(
        const <NodePathSegment>[],
        'routes',
        0,
      );
      final routes = (updated.root as RouteNode).childSlots['routes']!;
      expect(routes, hasLength(1));
      final remaining = routes.first as RouteNode;
      expect((remaining.properties['path'] as StringLiteralValue).value,
          equals('/about'));
    });

    test('moveChild reorders within a list slot', () {
      final updated = model.moveChild(
        const <NodePathSegment>[],
        'routes',
        0,
        1,
      );
      final routes = (updated.root as RouteNode).childSlots['routes']!;
      expect(routes, hasLength(2));
      final first = routes.first as RouteNode;
      expect((first.properties['path'] as StringLiteralValue).value,
          equals('/about'));
    });

    test('walk yields the root and every descendant', () {
      final entries = model.walk();
      expect(entries, hasLength(greaterThanOrEqualTo(3)));
      expect(entries.first.node, equals(model.root));
      expect(entries.first.path, isEmpty);
      // The descendants should include both GoRoutes.
      final descendantClassNames = entries
          .skip(1)
          .whereType<({NodePath path, ModelNode node})>()
          .map((e) => e.node)
          .whereType<RouteNode>()
          .map((r) => r.className)
          .toList();
      expect(descendantClassNames, contains('GoRoute'));
    });
  });
}
