import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loom_app/src/services/kernel_adapter.dart';
import 'package:loom_app/src/state/providers.dart';
import 'package:loom_app/src/surfaces/widget_outline/widget_tree_node_tile.dart';
import 'package:loom_app/src/surfaces/widget_outline/widget_tree_outline_view.dart';

import '../helpers/kernel_fixtures.dart';

void main() {
  testWidgets(
    'renders one tile per pre-order entry and shows class names',
    (tester) async {
      // Column → [Text, Text]
      final tree = treeOf(
        widgetNode(
          className: 'Column',
          childSlots: <String, List<ModelNode>>{
            'children': <ModelNode>[
              widgetNode(className: 'Text', offset: 10),
              widgetNode(className: 'Text', offset: 20),
            ],
          },
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            widgetTreeForDocumentProvider.overrideWith(
              (ref, uri) => WidgetTreeParseResult.modeled(tree),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: WidgetTreeOutlineView(
                documentUri: 'file:///test/main.dart',
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // 1 Column + 2 Text = 3 tiles.
      expect(find.byType(WidgetTreeNodeTile), findsNWidgets(3));
      expect(find.text('Column'), findsOneWidget);
      expect(find.text('Text'), findsNWidgets(2));
    },
  );

  testWidgets('shows parse-failure text on a failure result', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          widgetTreeForDocumentProvider.overrideWith(
            (ref, uri) => WidgetTreeParseResult.failure('boom!'),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: WidgetTreeOutlineView(
              documentUri: 'file:///test/main.dart',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('boom!'), findsOneWidget);
  });

  testWidgets('tapping a tile updates selectedNodePathProvider',
      (tester) async {
    final tree = treeOf(
      widgetNode(
        className: 'Column',
        childSlots: <String, List<ModelNode>>{
          'children': <ModelNode>[widgetNode(className: 'Text', offset: 10)],
        },
      ),
    );

    final container = ProviderContainer(
      overrides: <Override>[
        widgetTreeForDocumentProvider.overrideWith(
          (ref, uri) => WidgetTreeParseResult.modeled(tree),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: WidgetTreeOutlineView(
              documentUri: 'file:///test/main.dart',
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(container.read(selectedNodePathProvider), isNull);
    await tester.tap(find.text('Text'));
    await tester.pump();
    final selected = container.read(selectedNodePathProvider);
    expect(selected, isNotNull);
    expect(selected!.length, 1);
    expect(selected.first.slot, 'children');
    expect(selected.first.index, 0);
  });
}
