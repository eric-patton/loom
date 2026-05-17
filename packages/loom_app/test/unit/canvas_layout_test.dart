import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:loom_app/src/services/kernel_adapter.dart';
import 'package:loom_app/src/surfaces/widget_canvas/canvas_layout.dart';

import '../helpers/kernel_fixtures.dart';

void main() {
  const canvas = Rect.fromLTWH(0, 0, 400, 300);

  group('layoutTree', () {
    test('produces one rect per node in pre-order', () {
      final tree = treeOf(
        widgetNode(
          className: 'Column',
          childSlots: <String, List<ModelNode>>{
            'children': <ModelNode>[
              widgetNode(className: 'Text', offset: 10),
              widgetNode(className: 'Text', offset: 20),
              widgetNode(className: 'Text', offset: 30),
            ],
          },
        ),
      );
      final layout = layoutTree(tree, canvas);
      expect(layout.rects, hasLength(4));
      expect((layout.rects[0].node as WidgetNode).className, 'Column');
      expect(layout.rects[0].path, isEmpty);
      // The three Text children come next, in slot+index order.
      for (var i = 0; i < 3; i++) {
        expect((layout.rects[i + 1].node as WidgetNode).className, 'Text');
        expect(layout.rects[i + 1].path,
            <NodePathSegment>[(slot: 'children', index: i)]);
      }
    });

    test('Column children are stacked vertically with non-overlapping rects',
        () {
      final tree = treeOf(
        widgetNode(
          className: 'Column',
          childSlots: <String, List<ModelNode>>{
            'children': <ModelNode>[
              widgetNode(className: 'A', offset: 1),
              widgetNode(className: 'B', offset: 2),
            ],
          },
        ),
      );
      final layout = layoutTree(tree, canvas);
      final a = layout.rects[1].rect;
      final b = layout.rects[2].rect;
      // Same x extent, b below a.
      expect(a.left, b.left);
      expect(a.width, b.width);
      expect(a.bottom <= b.top + 4, isTrue,
          reason: 'A should sit above B; got $a / $b');
    });

    test('Row children are stacked horizontally', () {
      final tree = treeOf(
        widgetNode(
          className: 'Row',
          childSlots: <String, List<ModelNode>>{
            'children': <ModelNode>[
              widgetNode(className: 'A', offset: 1),
              widgetNode(className: 'B', offset: 2),
            ],
          },
        ),
      );
      final layout = layoutTree(tree, canvas);
      final a = layout.rects[1].rect;
      final b = layout.rects[2].rect;
      expect(a.top, b.top);
      expect(a.height, b.height);
      expect(a.right <= b.left + 4, isTrue,
          reason: 'A should sit left of B; got $a / $b');
    });

    test('Stack children all share the parent inner rect', () {
      final tree = treeOf(
        widgetNode(
          className: 'Stack',
          childSlots: <String, List<ModelNode>>{
            'children': <ModelNode>[
              widgetNode(className: 'A', offset: 1),
              widgetNode(className: 'B', offset: 2),
            ],
          },
        ),
      );
      final layout = layoutTree(tree, canvas);
      expect(layout.rects[1].rect, layout.rects[2].rect);
    });

    test('single-child wrapper insets the child inside the parent', () {
      final tree = treeOf(
        widgetNode(
          className: 'Padding',
          childSlots: <String, List<ModelNode>>{
            'child': <ModelNode>[widgetNode(className: 'Text', offset: 1)],
          },
        ),
      );
      final layout = layoutTree(tree, canvas);
      final parent = layout.rects[0].rect;
      final child = layout.rects[1].rect;
      expect(parent.contains(child.topLeft), isTrue);
      expect(parent.contains(child.bottomRight), isTrue);
      expect(child.width < parent.width, isTrue);
      expect(child.height < parent.height, isTrue);
    });

    test('does not recurse below the min-rect threshold', () {
      final tree = treeOf(
        widgetNode(
          className: 'Padding',
          childSlots: <String, List<ModelNode>>{
            'child': <ModelNode>[widgetNode(className: 'Text', offset: 1)],
          },
        ),
      );
      // Tiny canvas — inner area falls below the min-rect threshold.
      final layout = layoutTree(tree, const Rect.fromLTWH(0, 0, 20, 20));
      expect(layout.rects, hasLength(1));
      expect((layout.rects.single.node as WidgetNode).className, 'Padding');
    });

    test('Scaffold lays appBar at the top and body in the middle', () {
      final tree = treeOf(
        widgetNode(
          className: 'Scaffold',
          childSlots: <String, List<ModelNode>>{
            'appBar': <ModelNode>[widgetNode(className: 'AppBar', offset: 1)],
            'body': <ModelNode>[widgetNode(className: 'Center', offset: 2)],
          },
        ),
      );
      final layout = layoutTree(tree, canvas);
      final scaffold = layout.rects.first;
      expect((scaffold.node as WidgetNode).className, 'Scaffold');
      final appBar = layout.rects.firstWhere(
        (r) =>
            r.node is WidgetNode &&
            (r.node as WidgetNode).className == 'AppBar',
      );
      final body = layout.rects.firstWhere(
        (r) =>
            r.node is WidgetNode &&
            (r.node as WidgetNode).className == 'Center',
      );
      expect(appBar.rect.top, lessThan(body.rect.top),
          reason: 'AppBar should sit above the body');
      expect(appBar.rect.height, lessThanOrEqualTo(40),
          reason: 'AppBar slot height is fixed-small');
      expect(body.rect.height, greaterThan(appBar.rect.height));
    });
  });

  group('CanvasLayout.hitTest', () {
    test('returns deepest rect containing the point', () {
      final tree = treeOf(
        widgetNode(
          className: 'Column',
          childSlots: <String, List<ModelNode>>{
            'children': <ModelNode>[
              widgetNode(className: 'A', offset: 1),
              widgetNode(className: 'B', offset: 2),
            ],
          },
        ),
      );
      final layout = layoutTree(tree, canvas);
      final aRect = layout.rects[1].rect;
      final hit = layout.hitTest(aRect.center);
      expect(hit, isNotNull);
      expect((hit!.node as WidgetNode).className, 'A');
    });

    test('returns null when the point is outside the canvas', () {
      final tree = treeOf(widgetNode(className: 'X', offset: 1));
      final layout = layoutTree(tree, canvas);
      expect(layout.hitTest(const Offset(-1, -1)), isNull);
    });

    test('a point inside the parent label band hits the parent, not a child',
        () {
      final tree = treeOf(
        widgetNode(
          className: 'Column',
          childSlots: <String, List<ModelNode>>{
            'children': <ModelNode>[widgetNode(className: 'A', offset: 1)],
          },
        ),
      );
      final layout = layoutTree(tree, canvas);
      final parent = layout.rects[0].rect;
      // Point near the parent's top is in the label band, above the
      // child's inset region.
      final hit = layout.hitTest(Offset(parent.left + 8, parent.top + 6));
      expect(hit, isNotNull);
      expect((hit!.node as WidgetNode).className, 'Column');
    });
  });
}
