import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loom_app/src/inspectors/string_property_editor.dart';
import 'package:loom_app/src/shell/main_shell_screen.dart';
import 'package:loom_app/src/state/providers.dart';
import 'package:loom_app/src/surfaces/widget_canvas/widget_canvas_view.dart';

import '../helpers/test_workspace.dart';

/// End-to-end wiring proof for the M13 canvas. Opens the fixture, taps
/// the canvas to select a node, and asserts the inspector populates
/// with that node's editable properties — proving the
/// `selectedNodePathProvider` glue between the canvas and the
/// property inspector is hooked up the same way it was for the
/// outline.
void main() {
  testWidgets(
    'canvas tap updates selection and the inspector renders an editor',
    (tester) async {
      final session = await openFixtureSessionForWidgets(tester);
      addTearDown(session.dispose);

      session.container
          .read(workspaceControllerProvider)
          .openFile(session.counterUri);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: session.container,
          child: const MaterialApp(home: MainShellScreen()),
        ),
      );
      await tester.pump();

      // Canvas should render for the opened document.
      expect(find.byType(WidgetCanvasView), findsOneWidget);

      // Tap the center of the canvas. The deepest node at the center
      // will be some leaf widget in counter.dart — the exact identity
      // doesn't matter, only that the inspector picks it up.
      final canvas = find.byType(WidgetCanvasView);
      final center = tester.getCenter(canvas);
      final gesture = await tester.startGesture(center);
      await gesture.up();
      await tester.pumpAndSettle(const Duration(milliseconds: 600));

      // Selection wired up.
      expect(session.container.read(selectedNodePathProvider), isNotNull);

      // The inspector mounts editors for whichever node we selected.
      // We don't assert a specific count — just that the inspector
      // produced editable surface in response to the canvas tap.
      final inspectorEditorCount = tester
          .widgetList(
            find.byWidgetPredicate(
              (w) => w is StringPropertyEditor || w is Switch || w is TextField,
            ),
          )
          .length;
      expect(
        inspectorEditorCount,
        greaterThan(0),
        reason: 'A canvas tap should populate the property inspector',
      );
    },
  );
}
