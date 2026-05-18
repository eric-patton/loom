import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loom_app/src/services/kernel_adapter.dart';
import 'package:loom_app/src/state/providers.dart';
import 'package:loom_app/src/surfaces/widget_canvas/widget_canvas_view.dart';

import '../helpers/kernel_fixtures.dart';

/// Widget tests for the materializer's renderer catalog. Build a
/// hand-rolled WidgetNode for each renderer, pump the canvas, and
/// assert the materialized Flutter widget shows up with the expected
/// shape and property values.
void main() {
  group('NodeMaterializer renderers', () {
    testWidgets('Text materializes to a real Text with its data value',
        (tester) async {
      await _pumpCanvas(
        tester,
        widgetNode(
          className: 'Text',
          properties: <String, PropertyValue>{
            'data': stringValue('Hello, canvas!'),
          },
        ),
      );
      expect(find.text('Hello, canvas!'), findsOneWidget);
    });

    testWidgets('Column materializes with its modeled children in order',
        (tester) async {
      await _pumpCanvas(
        tester,
        widgetNode(
          className: 'Column',
          childSlots: <String, List<ModelNode>>{
            'children': <ModelNode>[
              widgetNode(
                className: 'Text',
                properties: <String, PropertyValue>{
                  'data': stringValue('first'),
                },
              ),
              widgetNode(
                className: 'Text',
                properties: <String, PropertyValue>{
                  'data': stringValue('second'),
                },
              ),
            ],
          },
        ),
      );
      expect(find.byType(Column), findsOneWidget);
      expect(find.text('first'), findsOneWidget);
      expect(find.text('second'), findsOneWidget);
    });

    testWidgets('Scaffold wraps body + appBar slots', (tester) async {
      await _pumpCanvas(
        tester,
        widgetNode(
          className: 'Scaffold',
          childSlots: <String, List<ModelNode>>{
            'appBar': <ModelNode>[
              widgetNode(
                className: 'AppBar',
                childSlots: <String, List<ModelNode>>{
                  'title': <ModelNode>[
                    widgetNode(
                      className: 'Text',
                      properties: <String, PropertyValue>{
                        'data': stringValue('Title'),
                      },
                    ),
                  ],
                },
              ),
            ],
            'body': <ModelNode>[
              widgetNode(
                className: 'Center',
                childSlots: <String, List<ModelNode>>{
                  'child': <ModelNode>[
                    widgetNode(
                      className: 'Text',
                      properties: <String, PropertyValue>{
                        'data': stringValue('Body'),
                      },
                    ),
                  ],
                },
              ),
            ],
          },
        ),
      );
      expect(find.byType(Scaffold), findsAtLeastNWidgets(1));
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('Title'), findsOneWidget);
      expect(find.text('Body'), findsOneWidget);
      expect(find.byType(Center), findsOneWidget);
    });

    testWidgets('Padding materializes with EdgeInsetsAllValue', (tester) async {
      await _pumpCanvas(
        tester,
        widgetNode(
          className: 'Padding',
          properties: <String, PropertyValue>{
            'padding': EdgeInsetsAllValue(
              amount: 12.0,
              amountIsDouble: true,
              span: const SourceSpan(offset: 0, length: 16),
            ),
          },
          childSlots: <String, List<ModelNode>>{
            'child': <ModelNode>[
              widgetNode(
                className: 'Text',
                properties: <String, PropertyValue>{
                  'data': stringValue('padded'),
                },
              ),
            ],
          },
        ),
      );
      final paddingFinder = find.byType(Padding);
      expect(paddingFinder, findsAtLeastNWidgets(1));
      // The materializer's Padding widget is somewhere in the tree;
      // grab the one whose padding matches.
      final paddings = tester.widgetList<Padding>(paddingFinder);
      expect(
        paddings.any((p) => p.padding == const EdgeInsets.all(12)),
        isTrue,
        reason: 'expected at least one Padding with padding=EdgeInsets.all(12)',
      );
      expect(find.text('padded'), findsOneWidget);
    });

    testWidgets('Visibility honors the visible property', (tester) async {
      await _pumpCanvas(
        tester,
        widgetNode(
          className: 'Visibility',
          properties: <String, PropertyValue>{
            'visible': boolValue(false),
          },
          childSlots: <String, List<ModelNode>>{
            'child': <ModelNode>[
              widgetNode(
                className: 'Text',
                properties: <String, PropertyValue>{
                  'data': stringValue('hidden'),
                },
              ),
            ],
          },
        ),
      );
      final visibilities =
          tester.widgetList<Visibility>(find.byType(Visibility));
      expect(
        visibilities.any((v) => v.visible == false),
        isTrue,
        reason: 'expected at least one Visibility with visible=false',
      );
    });

    testWidgets(
        'Unknown className renders the placeholder, descends into children',
        (tester) async {
      await _pumpCanvas(
        tester,
        widgetNode(
          className: 'FancyHypotheticalWidget',
          childSlots: <String, List<ModelNode>>{
            'child': <ModelNode>[
              widgetNode(
                className: 'Text',
                properties: <String, PropertyValue>{
                  'data': stringValue('inside'),
                },
              ),
            ],
          },
        ),
      );
      // The className shows in the placeholder's label band.
      expect(find.text('FancyHypotheticalWidget'), findsOneWidget);
      // And we still descend, so the inner Text renders.
      expect(find.text('inside'), findsOneWidget);
    });
  });
}

/// Pumps WidgetCanvasView with [root] as the modeled tree for a known
/// document URI, then settles a frame.
Future<void> _pumpCanvas(WidgetTester tester, ModelNode root) async {
  const uri = 'file:///test/main.dart';
  final container = ProviderContainer(
    overrides: <Override>[
      widgetTreeForDocumentProvider.overrideWith(
        (ref, _) => WidgetTreeParseResult.modeled(treeOf(root)),
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
            child: WidgetCanvasView(documentUri: uri),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
