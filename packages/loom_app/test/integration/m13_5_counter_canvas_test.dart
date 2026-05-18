import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loom_app/src/shell/main_shell_screen.dart';
import 'package:loom_app/src/state/providers.dart';
import 'package:loom_app/src/surfaces/widget_canvas/widget_canvas_view.dart';

import '../helpers/test_workspace.dart';

/// Load-bearing M13.5 acceptance test: with main.dart open in the
/// editor, the canvas materializes the resolved `Counter` (declared in
/// `lib/widgets/counter.dart`) and renders its actual Text children —
/// proving cross-file user-widget resolution drives all the way to
/// pixels.
void main() {
  testWidgets(
    'canvas materializes a user widget into its declared build tree',
    (tester) async {
      final session = await openFixtureSessionForWidgets(tester);
      addTearDown(session.dispose);

      session.container
          .read(workspaceControllerProvider)
          .openFile(session.mainUri);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: session.container,
          child: const MaterialApp(home: MainShellScreen()),
        ),
      );
      await tester.pump();
      await tester.pump();

      // Canvas is the active surface for main.dart.
      expect(find.byType(WidgetCanvasView), findsOneWidget);

      // The Counter widget reference in main.dart resolves to its
      // build body in counter.dart — and the canvas materializes its
      // Text children for real.
      expect(find.text('Hello'), findsOneWidget);
      expect(find.text('World'), findsOneWidget);
      expect(find.text('Click me'), findsOneWidget);
      expect(find.text('Visible'), findsOneWidget);
    },
  );
}
