import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loom_app/src/shell/right_pane/tabs/interface_tab.dart';

import '../helpers/test_workspace.dart';

void main() {
  testWidgets('lists the modeled files when a project is open', (tester) async {
    final session = await openFixtureSessionForWidgets(tester);
    addTearDown(session.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: session.container,
        child: const MaterialApp(
          home: Scaffold(body: InterfaceTab()),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('main.dart'), findsOneWidget);
    expect(find.textContaining('counter.dart'), findsOneWidget);
  });

  testWidgets('shows the no-project message when nothing is open',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: InterfaceTab()),
        ),
      ),
    );
    expect(find.textContaining('No project open'), findsOneWidget);
  });
}
