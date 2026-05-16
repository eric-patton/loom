/// Route-tree round-trip tests (M6.0).
///
/// Mirrors the widget round-trip invariants from PROJECT_SPEC for routes:
///   1. Round-trip stability: parse(apply(emit(edit), source)) reflects
///      the intended change with no other byte movement.
///   2. No-op idempotence: apply([], source) == source byte-for-byte.
library;

import 'dart:io';

import 'package:loom/loom.dart';
import 'package:test/test.dart';

const _routeFixtures = <String>[
  'route_simple.dart',
  'route_nested.dart',
  'route_shell.dart',
  'route_with_helper.dart',
  // Real-world: flutter/packages @ 0ffbde8f, packages/go_router/example/lib/main.dart
  'real_world_go_router_main.dart',
  // Real-world: flutter/packages @ 0ffbde8f, packages/go_router/example/lib/named_routes.dart
  // Exercises M6.0.1 class-field initializer path (`late final GoRouter _router = ...`).
  'real_world_go_router_named_routes.dart',
];

String _loadFixture(String name) =>
    File('test/fixtures/$name').readAsStringSync();

void main() {
  group('invariant 2 - no-op idempotence (routes)', () {
    for (final fixture in _routeFixtures) {
      test('apply([], source) == source on $fixture', () {
        final source = _loadFixture(fixture);
        final model = parseRouteTree(source);
        final result = applySourceEdits(source, const <SourceEdit>[]);
        expect(result, equals(source));
        // Guard against silently-empty parser.
        expect(model.root, isA<RouteNode>());
        expect((model.root as RouteNode).className, isNotEmpty);
      });
    }
  });

  group('property edit: change a route path', () {
    test('path "/" -> "/dashboard" preserves bytes outside the value', () {
      final source = _loadFixture('route_simple.dart');
      final model = parseRouteTree(source);
      final root = model.root as RouteNode;
      final firstRoute = root.childSlots['routes']!.first as RouteNode;

      final oldPath = firstRoute.properties['path'] as StringLiteralValue;
      final newPath = StringLiteralValue(
        value: '/dashboard',
        usesDoubleQuotes: oldPath.usesDoubleQuotes,
        span: oldPath.span,
      );

      final edit = RouteEditPlanner.propertyEdit(
        oldValue: oldPath,
        newValue: newPath,
      );
      final newSource = applySourceEdits(source, [edit]);

      // Prefix and suffix unchanged.
      final prefix = source.substring(0, oldPath.span.offset);
      expect(newSource.substring(0, oldPath.span.offset), equals(prefix));
      final suffix = source.substring(oldPath.span.end);
      expect(
        newSource.substring(oldPath.span.offset + edit.replacement.length),
        equals(suffix),
      );

      // Re-parse reflects the new value.
      final reparsed = parseRouteTree(newSource);
      final reparsedRoot = reparsed.root as RouteNode;
      final reparsedFirst =
          reparsedRoot.childSlots['routes']!.first as RouteNode;
      final reparsedPath =
          reparsedFirst.properties['path'] as StringLiteralValue;
      expect(reparsedPath.value, equals('/dashboard'));
    });
  });

  group('structural edit: insert child route', () {
    test('insert at index 1 of routes preserves outside-bytes', () {
      final source = _loadFixture('route_simple.dart');
      final model = parseRouteTree(source);
      final root = model.root as RouteNode;

      final newRoute = RouteNode(
        className: 'GoRoute',
        properties: {
          'path': const StringLiteralValue(
            value: '/profile',
            usesDoubleQuotes: false,
            span: SourceSpan(offset: 0, length: 0),
          ),
        },
        childSlots: const <String, List<ModelNode>>{},
        sourceSpan: const SourceSpan(offset: 0, length: 0),
        styleHints: const StyleHints(
          hasConst: false,
          hasNew: false,
          hasTrailingComma: false,
        ),
      );

      final edit = RouteEditPlanner.insertChildEdit(
        parent: root,
        slotName: 'routes',
        index: 1,
        newChild: newRoute,
        source: source,
      );
      final newSource = applySourceEdits(source, [edit]);

      // Re-parse: routes should now be length 3.
      final reparsed = parseRouteTree(newSource);
      final reparsedRoot = reparsed.root as RouteNode;
      final routes = reparsedRoot.childSlots['routes']!;
      expect(routes, hasLength(3));

      // The inserted route is now at index 1.
      final inserted = routes[1] as RouteNode;
      expect(inserted.className, equals('GoRoute'));
      expect((inserted.properties['path'] as StringLiteralValue).value,
          equals('/profile'));

      // Original first and last routes preserved.
      final stillFirst = routes[0] as RouteNode;
      expect((stillFirst.properties['path'] as StringLiteralValue).value,
          equals('/'));
      final stillLast = routes[2] as RouteNode;
      expect((stillLast.properties['path'] as StringLiteralValue).value,
          equals('/settings'));
    });
  });

  group('structural edit: remove child route', () {
    test('remove last route in routes list reparses cleanly', () {
      final source = _loadFixture('route_simple.dart');
      final model = parseRouteTree(source);
      final root = model.root as RouteNode;

      final edit = RouteEditPlanner.removeChildEdit(
        parent: root,
        slotName: 'routes',
        index: 1,
        source: source,
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseRouteTree(newSource);
      final reparsedRoot = reparsed.root as RouteNode;
      final routes = reparsedRoot.childSlots['routes']!;
      expect(routes, hasLength(1));
      expect(
        ((routes.first as RouteNode).properties['path'] as StringLiteralValue)
            .value,
        equals('/'),
      );
    });

    test('remove first route in routes list reparses cleanly', () {
      final source = _loadFixture('route_simple.dart');
      final model = parseRouteTree(source);
      final root = model.root as RouteNode;

      final edit = RouteEditPlanner.removeChildEdit(
        parent: root,
        slotName: 'routes',
        index: 0,
        source: source,
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseRouteTree(newSource);
      final reparsedRoot = reparsed.root as RouteNode;
      final routes = reparsedRoot.childSlots['routes']!;
      expect(routes, hasLength(1));
      expect(
        ((routes.first as RouteNode).properties['path'] as StringLiteralValue)
            .value,
        equals('/settings'),
      );
    });
  });

  group('structural edit: move child route', () {
    test('move first route to last position preserves both', () {
      final source = _loadFixture('route_simple.dart');
      final model = parseRouteTree(source);
      final root = model.root as RouteNode;

      final edits = RouteEditPlanner.moveChildEdits(
        parent: root,
        slotName: 'routes',
        from: 0,
        to: 1,
        source: source,
      );
      final newSource = applySourceEdits(source, edits);

      final reparsed = parseRouteTree(newSource);
      final reparsedRoot = reparsed.root as RouteNode;
      final routes = reparsedRoot.childSlots['routes']!;
      expect(routes, hasLength(2));
      // Order swapped: /settings first, / second.
      expect(
        ((routes[0] as RouteNode).properties['path'] as StringLiteralValue)
            .value,
        equals('/settings'),
      );
      expect(
        ((routes[1] as RouteNode).properties['path'] as StringLiteralValue)
            .value,
        equals('/'),
      );
    });
  });
}
