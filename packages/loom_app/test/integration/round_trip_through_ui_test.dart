import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loom_app/src/inspectors/string_property_editor.dart';
import 'package:loom_app/src/services/kernel_adapter.dart';
import 'package:loom_app/src/shell/main_shell_screen.dart';
import 'package:loom_app/src/state/providers.dart';

import '../helpers/test_workspace.dart';

/// End-to-end wiring proof: pumps `MainShellScreen`, opens the M11
/// counter fixture, selects a known `Text` node via the outline path
/// API, enters new text in the inspector's `StringPropertyEditor`,
/// triggers commit, and asserts the change reached disk. The
/// 100-iteration stress test lives in
/// `multi_property_edits_round_trip_test.dart`; this one is the
/// acceptance demo's scripted slice.
void main() {
  testWidgets(
    'select Text → edit data in inspector → disk reflects the new literal',
    (tester) async {
      final session = await openFixtureSessionForWidgets(tester);
      addTearDown(session.dispose);

      // Open the counter file so its outline is the active surface.
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

      const adapter = KernelAdapter();

      // Parse the on-disk source to locate the first Text widget that
      // has a string `data` property. This is `Text('Hello')` per the
      // pinned fixture.
      final source =
          await tester.runAsync<String>(() => session.readCounterSource());
      final parse = adapter.parseWidgetTreeFor(source: source!);
      expect(parse, isA<WidgetTreeParseModeled>());
      final model = (parse as WidgetTreeParseModeled).model;

      final entries = model.walk();
      final firstTextData = entries.firstWhere((e) {
        final n = e.node;
        return n is WidgetNode &&
            n.className == 'Text' &&
            n.properties['data'] is StringLiteralValue;
      });
      final oldValue = (firstTextData.node as WidgetNode).properties['data']!
          as StringLiteralValue;
      expect(oldValue.value, 'Hello');

      // Drive selection through the public state slice. The outline-tile
      // tap is exercised separately in `widget_tree_outline_view_test`.
      session.container.read(selectedNodeProvider.notifier).state =
          (documentUri: session.counterUri, path: firstTextData.path);
      await tester.pump();

      // The inspector should now render exactly one StringPropertyEditor
      // (Text's `data:` is its only modeled string property).
      final stringEditorFinder = find.byType(StringPropertyEditor);
      expect(stringEditorFinder, findsOneWidget);
      final textField = find.descendant(
        of: stringEditorFinder,
        matching: find.byType(TextField),
      );
      expect(textField, findsOneWidget);

      // Enter the new literal. `enterText` runs inside the fake-async
      // zone — fine for setting the controller's text, but the
      // editor's commit pipeline awaits real disk I/O. Wrap the
      // focus-loss + I/O wait in `runAsync` so the dart:io Futures
      // actually complete before we re-read disk.
      await tester.enterText(textField, 'World');
      await tester.pump();
      await tester.runAsync(() async {
        tester.binding.focusManager.primaryFocus?.unfocus();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();

      // Disk now reflects the new literal.
      final after =
          await tester.runAsync<String>(() => session.readCounterSource());
      expect(after, contains("'World'"));
      expect(after, isNot(contains("'Hello'")));

      // Source still parses cleanly.
      final reparse = adapter.parseWidgetTreeFor(source: after!);
      expect(reparse, isA<WidgetTreeParseModeled>());
    },
  );
}
