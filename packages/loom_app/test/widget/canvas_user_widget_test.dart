import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loom_app/src/services/kernel_adapter.dart';
import 'package:loom_app/src/state/providers.dart';
import 'package:loom_app/src/surfaces/widget_canvas/widget_canvas_view.dart';

import '../helpers/kernel_fixtures.dart';

/// Proves that the materializer recurses into user-defined widgets via
/// `userWidgetResolutionProvider`: when the canvas's tree contains a
/// `WidgetNode(className: 'Counter')` and the resolver hands back
/// Counter's build tree, the canvas renders the resolved content
/// instead of a placeholder.
///
/// Real cross-file resolution needs a live ProjectWidgetIndex — those
/// pieces are exercised by `m13_5_counter_canvas_test.dart`. Here we
/// override the resolver directly so we can isolate the materializer's
/// recursion logic from kernel parsing.
void main() {
  testWidgets(
    'renders the resolved tree when a user widget is referenced',
    (tester) async {
      // The "outer" document references `Counter()` as its only widget.
      final outerTree = treeOf(widgetNode(className: 'Counter'));

      // The kernel "would" resolve Counter to this build tree.
      final counterResolution = WidgetTreeParseResult.modeled(
        treeOf(
          widgetNode(
            className: 'Scaffold',
            childSlots: <String, List<ModelNode>>{
              'body': <ModelNode>[
                widgetNode(
                  className: 'Center',
                  childSlots: <String, List<ModelNode>>{
                    'child': <ModelNode>[
                      widgetNode(
                        className: 'Text',
                        properties: <String, PropertyValue>{
                          'data': stringValue('inside Counter'),
                        },
                      ),
                    ],
                  },
                ),
              ],
            },
          ),
        ),
      );

      const outerUri = 'file:///test/main.dart';
      const counterUri = 'file:///test/widgets/counter.dart';

      final container = ProviderContainer(
        overrides: <Override>[
          widgetTreeForDocumentProvider.overrideWith(
            (ref, uri) => WidgetTreeParseResult.modeled(outerTree),
          ),
          userWidgetResolutionProvider.overrideWith(
            (ref, key) {
              if (key.className == 'Counter') return counterResolution;
              return null;
            },
          ),
          // The materializer reads declaringFileOf via
          // `projectWidgetIndexProvider`. Override the project model + index
          // so it returns the fake declaring file for 'Counter'.
          projectModelProvider.overrideWith(
            (ref) => ProjectModel.fromSources(<String, String>{
              counterUri: 'class Counter extends StatelessWidget {'
                  '  @override Widget build(BuildContext c) =>'
                  '    const Scaffold(body: Center(child: Text("inside Counter")));'
                  '}',
            }),
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
                width: 800,
                height: 600,
                child: WidgetCanvasView(documentUri: outerUri),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // The resolved Counter tree's contents render on the canvas —
      // proving the materializer recursed instead of placeholdering.
      expect(find.text('inside Counter'), findsOneWidget);
      // And the Scaffold from Counter's resolved tree is present too.
      expect(find.byType(Scaffold), findsAtLeastNWidgets(2));
    },
  );

  testWidgets(
    'unresolved user widget shows the placeholder, still descends',
    (tester) async {
      final outerTree = treeOf(
        widgetNode(
          className: 'NotAFrameworkWidget',
          childSlots: <String, List<ModelNode>>{
            'child': <ModelNode>[
              widgetNode(
                className: 'Text',
                properties: <String, PropertyValue>{
                  'data': stringValue('still here'),
                },
              ),
            ],
          },
        ),
      );

      const outerUri = 'file:///test/main.dart';

      final container = ProviderContainer(
        overrides: <Override>[
          widgetTreeForDocumentProvider.overrideWith(
            (ref, uri) => WidgetTreeParseResult.modeled(outerTree),
          ),
          userWidgetResolutionProvider.overrideWith(
            (ref, key) => const WidgetTreeParseFailure('not visible'),
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
                width: 800,
                height: 600,
                child: WidgetCanvasView(documentUri: outerUri),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // The placeholder shows the className label.
      expect(find.text('NotAFrameworkWidget'), findsOneWidget);
      // And we still recurse into modeled children even though the
      // class itself isn't resolvable.
      expect(find.text('still here'), findsOneWidget);
    },
  );
}
