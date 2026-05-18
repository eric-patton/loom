import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loom_app/src/inspectors/opaque_property_readout.dart';
import 'package:loom_app/src/inspectors/string_property_editor.dart';
import 'package:loom_app/src/services/kernel_adapter.dart';
import 'package:loom_app/src/shell/right_pane/property_inspector/property_inspector_panel.dart';
import 'package:loom_app/src/state/providers.dart';

import '../helpers/kernel_fixtures.dart';

void main() {
  testWidgets(
    'shows one row per editable property of the selected WidgetNode',
    (tester) async {
      final node = widgetNode(
        className: 'Text',
        properties: <String, PropertyValue>{
          'data': stringValue('hi'),
          'overflow': enumRef('TextOverflow', 'ellipsis'),
        },
      );
      final tree = treeOf(node);

      final container = ProviderContainer(
        overrides: <Override>[
          activeDocumentUriProvider.overrideWith(
            (ref) => 'file:///test/main.dart',
          ),
          selectedNodeProvider.overrideWith(
            (ref) => (
              documentUri: 'file:///test/main.dart',
              path: const <NodePathSegment>[],
            ),
          ),
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
            home: Scaffold(body: PropertyInspectorPanel()),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('data'), findsOneWidget);
      expect(find.text('overflow'), findsOneWidget);
      expect(find.byType(StringPropertyEditor), findsOneWidget);
      expect(find.byType(OpaquePropertyReadout), findsOneWidget);
    },
  );

  testWidgets('shows idle text when no node is selected', (tester) async {
    final container = ProviderContainer(
      overrides: <Override>[
        activeDocumentUriProvider.overrideWith(
          (ref) => 'file:///test/main.dart',
        ),
        widgetTreeForDocumentProvider.overrideWith(
          (ref, uri) => WidgetTreeParseResult.modeled(
            treeOf(widgetNode(className: 'X')),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: PropertyInspectorPanel()),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('Select a node'), findsOneWidget);
  });

  testWidgets(
    'shows "no editable properties" when WidgetNode has no modeled props',
    (tester) async {
      final node = widgetNode(className: 'SizedBox');
      final tree = treeOf(node);

      final container = ProviderContainer(
        overrides: <Override>[
          activeDocumentUriProvider.overrideWith(
            (ref) => 'file:///test/main.dart',
          ),
          selectedNodeProvider.overrideWith(
            (ref) => (
              documentUri: 'file:///test/main.dart',
              path: const <NodePathSegment>[],
            ),
          ),
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
            home: Scaffold(body: PropertyInspectorPanel()),
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining('no editable properties'), findsOneWidget);
    },
  );
}
