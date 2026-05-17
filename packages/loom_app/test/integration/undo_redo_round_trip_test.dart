import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:loom_app/src/services/kernel_adapter.dart';
import 'package:loom_app/src/state/providers.dart';

import '../helpers/test_workspace.dart';

/// The M12 acceptance test. Apply ten distinct property edits through
/// `WorkspaceController.applyPropertyEdit`, then call `undo()` ten
/// times, and assert the file's bytes equal the original on-disk
/// content exactly. This is the editor's "10 edits, undo all, git diff
/// empty" promise from the M12 plan, verified at the controller level.
void main() {
  testWidgets(
    '10 property edits + 10 undos restores the file byte-for-byte',
    (tester) async {
      final session = await openFixtureSessionForWidgets(tester);
      addTearDown(session.dispose);

      session.container
          .read(workspaceControllerProvider)
          .openFile(session.counterUri);

      const adapter = KernelAdapter();
      final rng = Random(2026);

      final original = await tester.runAsync<String>(
          () async => File(session.counterDiskPath).readAsString());
      expect(original, isNotNull);

      for (var i = 0; i < 10; i++) {
        final source =
            await tester.runAsync<String>(() => session.readCounterSource());
        final parse = adapter.parseWidgetTreeFor(source: source!);
        expect(parse, isA<WidgetTreeParseModeled>(),
            reason: 'iter $i: parse failed for source\n$source');
        final model = (parse as WidgetTreeParseModeled).model;

        final editable = <_Pick>[];
        for (final entry in model.walk()) {
          final n = entry.node;
          if (n is! WidgetNode) continue;
          for (final pe in n.properties.entries) {
            final v = pe.value;
            if (v is StringLiteralValue ||
                v is NumLiteralValue ||
                v is BoolLiteralValue) {
              editable.add(_Pick(pe.value));
            }
          }
        }
        expect(editable, isNotEmpty);

        final pick = editable[rng.nextInt(editable.length)];
        final mutated = _mutate(pick.value, rng, i);
        final ok = await tester.runAsync<bool>(() => session.container
            .read(workspaceControllerProvider)
            .applyPropertyEdit(
              uri: session.counterUri,
              oldValue: pick.value,
              newValue: mutated,
            ));
        expect(ok, isTrue, reason: 'iter $i: applyPropertyEdit returned false');
        await tester.pump();
      }

      final afterEdits =
          await tester.runAsync<String>(() => session.readCounterSource());
      expect(afterEdits, isNot(original),
          reason: 'sanity: 10 edits should change the file');

      for (var i = 0; i < 10; i++) {
        final ok = await tester.runAsync<bool>(
            () => session.container.read(workspaceControllerProvider).undo());
        expect(ok, isTrue, reason: 'undo $i returned false');
        await tester.pump();
      }

      final afterUndo =
          await tester.runAsync<String>(() => session.readCounterSource());
      expect(
        afterUndo,
        original,
        reason: 'After undoing all 10 edits the file should be byte-identical '
            'to its original content. A divergence means the history snapshots '
            'do not faithfully restore prior state.',
      );

      // After 10 undos every redo should restore the same final state we had
      // after the 10 edits — proving the redo stack mirrors the undo path.
      for (var i = 0; i < 10; i++) {
        final ok = await tester.runAsync<bool>(
            () => session.container.read(workspaceControllerProvider).redo());
        expect(ok, isTrue, reason: 'redo $i returned false');
        await tester.pump();
      }
      final afterRedo =
          await tester.runAsync<String>(() => session.readCounterSource());
      expect(afterRedo, afterEdits,
          reason: '10 redos should re-create the post-edit state byte-exact.');

      // A fresh edit after a partial undo must drop the redo stack.
      // First, undo once to put something on the redo stack.
      final undoneOnce = await tester.runAsync<bool>(
          () => session.container.read(workspaceControllerProvider).undo());
      expect(undoneOnce, isTrue);
      await tester.pump();

      // Now make an arbitrary edit.
      final source =
          await tester.runAsync<String>(() => session.readCounterSource());
      final parse = adapter.parseWidgetTreeFor(source: source!);
      final model = (parse as WidgetTreeParseModeled).model;
      StringLiteralValue? pick;
      for (final entry in model.walk()) {
        final n = entry.node;
        if (n is! WidgetNode) continue;
        for (final pe in n.properties.entries) {
          if (pe.value is StringLiteralValue) {
            pick = pe.value as StringLiteralValue;
            break;
          }
        }
        if (pick != null) break;
      }
      expect(pick, isNotNull);

      final edited = StringLiteralValue(
        value: 'after-redo-discard',
        usesDoubleQuotes: pick!.usesDoubleQuotes,
        span: pick.span,
      );
      final ok = await tester.runAsync<bool>(() =>
          session.container.read(workspaceControllerProvider).applyPropertyEdit(
                uri: session.counterUri,
                oldValue: pick!,
                newValue: edited,
              ));
      expect(ok, isTrue);
      await tester.pump();

      // The redo stack should now be empty.
      final history =
          session.container.read(editHistoryProvider)[session.counterUri];
      expect(history?.canRedo, isFalse,
          reason:
              'Recording a new edit after an undo must drop the redo stack.');
    },
  );
}

class _Pick {
  _Pick(this.value);
  final PropertyValue value;
}

PropertyValue _mutate(PropertyValue v, Random rng, int seed) {
  return switch (v) {
    StringLiteralValue() => StringLiteralValue(
        value: 'undo_${seed}_${rng.nextInt(1 << 30)}',
        usesDoubleQuotes: v.usesDoubleQuotes,
        span: v.span,
      ),
    NumLiteralValue() => NumLiteralValue(
        value: v.isDouble ? rng.nextDouble() * 100 : rng.nextInt(1000),
        isDouble: v.isDouble,
        span: v.span,
      ),
    BoolLiteralValue() => BoolLiteralValue(
        value: !v.value,
        span: v.span,
      ),
    _ => throw StateError('_mutate received non-editable: $v'),
  };
}
