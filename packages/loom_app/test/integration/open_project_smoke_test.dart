import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loom_app/src/shell/main_shell_screen.dart';

import '../helpers/test_workspace.dart';

void main() {
  testWidgets(
    'open project shows files in Interface tab and renders outline on file '
    'open',
    (tester) async {
      final session = await openFixtureSessionForWidgets(tester);
      addTearDown(session.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: session.container,
          child: const MaterialApp(home: MainShellScreen()),
        ),
      );
      await tester.pump();

      // Interface tab default — file list rendered.
      expect(find.textContaining('main.dart'), findsOneWidget);
      expect(find.textContaining('widgets/counter.dart'), findsOneWidget);

      // Tap counter.dart to open it.
      await tester.tap(find.textContaining('widgets/counter.dart'));
      await tester.pump();

      // Center pane now shows the widget outline. counter.dart's root is
      // Scaffold (Center → Column → ...).
      expect(find.text('Scaffold'), findsAtLeastNWidgets(1));
      expect(find.text('Column'), findsAtLeastNWidgets(1));
      expect(find.text('Text'), findsAtLeastNWidgets(1));
    },
  );
}
