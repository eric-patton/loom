import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loom_app/src/services/kernel_adapter.dart';
import 'package:loom_app/src/state/providers.dart';
import 'package:loom_app/src/surfaces/widget_canvas/inline_text_edit_state.dart';
import 'package:loom_app/src/surfaces/widget_canvas/inline_text_editor.dart';
import 'package:loom_app/src/surfaces/widget_canvas/widget_canvas_view.dart';

import '../helpers/kernel_fixtures.dart';

Future<void> _pumpCanvas(
  WidgetTester tester, {
  required ProviderContainer container,
  required WidgetTreeModel tree,
  String documentUri = 'file:///test/main.dart',
}) async {
  // Override the parse provider so the canvas reads our fixture tree
  // without hitting disk.
  final overridden = ProviderContainer(
    overrides: <Override>[
      widgetTreeForDocumentProvider.overrideWith(
        (ref, uri) => WidgetTreeParseResult.modeled(tree),
      ),
    ],
  );
  addTearDown(overridden.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: overridden,
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 400,
            child: WidgetCanvasView(documentUri: documentUri),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  // Hand the supplied container back to the caller so its provider
  // overrides remain accessible.
  return;
}

void main() {
  testWidgets('renders a CustomPaint for the layout', (tester) async {
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
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _pumpCanvas(tester, container: container, tree: tree);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('shows parse-failure text on a failure result', (tester) async {
    final container = ProviderContainer(
      overrides: <Override>[
        widgetTreeForDocumentProvider.overrideWith(
          (ref, uri) => WidgetTreeParseResult.failure('boom!'),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: WidgetCanvasView(documentUri: 'file:///test/main.dart'),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('boom!'), findsOneWidget);
  });

  testWidgets('tap on canvas updates selectedNodePathProvider', (tester) async {
    final tree = treeOf(
      widgetNode(
        className: 'Column',
        childSlots: <String, List<ModelNode>>{
          'children': <ModelNode>[
            widgetNode(className: 'Text', offset: 10),
          ],
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
            body: SizedBox(
              width: 600,
              height: 400,
              child: WidgetCanvasView(documentUri: 'file:///test/main.dart'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(container.read(selectedNodePathProvider), isNull);

    // Tap the canvas. We drive the gesture explicitly so the test
    // framework's gesture arbiter does not deadlock between the
    // `onTapDown` and `onDoubleTapDown` recognizers on the same
    // detector — `tap`/`tapAt` calls can hang in this configuration.
    final canvas = find.byType(WidgetCanvasView);
    final center = tester.getCenter(canvas);
    final gesture = await tester.startGesture(center);
    await gesture.up();
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    final selected = container.read(selectedNodePathProvider);
    expect(selected, isNotNull);
  });

  testWidgets(
    'double-tap on a Text widget opens an InlineTextEditor',
    (tester) async {
      final tree = treeOf(
        widgetNode(
          className: 'Text',
          properties: <String, PropertyValue>{
            'data': stringValue('Hello', offset: 0),
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
              body: SizedBox(
                width: 400,
                height: 300,
                child: WidgetCanvasView(documentUri: 'file:///test/main.dart'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Double-tap the canvas center — the only widget is Text. The
      // two press/release cycles need to land inside `kDoubleTapTimeout`
      // (~300ms) for the gesture arbiter to recognize a double-tap.
      final canvas = find.byType(WidgetCanvasView);
      final center = tester.getCenter(canvas);
      final first = await tester.startGesture(center);
      await first.up();
      await tester.pump(const Duration(milliseconds: 50));
      final second = await tester.startGesture(center);
      await second.up();
      await tester.pumpAndSettle(const Duration(milliseconds: 600));

      final edit = container.read(inlineTextEditProvider);
      expect(edit, isNotNull);
      expect(edit!.original.value, 'Hello');
      expect(find.byType(InlineTextEditor), findsOneWidget);
    },
  );
}
