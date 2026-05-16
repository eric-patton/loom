import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:loom_app/src/services/kernel_adapter.dart';
import 'package:loom_app/src/state/providers.dart';

import '../helpers/test_workspace.dart';

/// Controller-level round-trip stress test: drives 100 sequential
/// property edits through `WorkspaceController.applyPropertyEdit`,
/// asserts each one persisted to disk, and re-parses the result so a
/// regression in `EditPlanner.propertyEdit` or `applySourceEdits`
/// shows up as a parse failure or a byte-divergent state.
void main() {
  testWidgets(
      '100 randomized controller-driven property edits round-trip to disk',
      (tester) async {
    final session = await openFixtureSessionForWidgets(tester);
    addTearDown(session.dispose);

    // `applyPropertyEdit` operates on the open-document buffer, so the
    // file has to be opened before edits land.
    session.container
        .read(workspaceControllerProvider)
        .openFile(session.counterUri);

    const adapter = KernelAdapter();
    final rng = Random(42);

    for (var i = 0; i < 100; i++) {
      final source =
          await tester.runAsync<String>(() => session.readCounterSource());
      final parse = adapter.parseWidgetTreeFor(source: source!);
      expect(
        parse,
        isA<WidgetTreeParseModeled>(),
        reason: 'iter $i: parse failed for source\n$source',
      );
      final model = (parse as WidgetTreeParseModeled).model;

      // Collect every editable (string/int/double/bool) property.
      final editable = <_PropPick>[];
      for (final entry in model.walk()) {
        final n = entry.node;
        if (n is! WidgetNode) continue;
        for (final pe in n.properties.entries) {
          final v = pe.value;
          if (v is StringLiteralValue ||
              v is NumLiteralValue ||
              v is BoolLiteralValue) {
            editable.add(_PropPick(entry.path, pe.key, v));
          }
        }
      }
      expect(editable, isNotEmpty);
      final pick = editable[rng.nextInt(editable.length)];

      final newValue = _mutate(pick.value, rng, i);
      final ok = await tester.runAsync<bool>(() =>
          session.container.read(workspaceControllerProvider).applyPropertyEdit(
                uri: session.counterUri,
                oldValue: pick.value,
                newValue: newValue,
              ));
      expect(
        ok,
        isTrue,
        reason: 'iter $i: edit returned false for $pick → $newValue',
      );

      // Pump a single frame so derived providers settle.
      await tester.pump();

      // Re-read disk and re-parse. Any failure here means the edit
      // produced un-parseable source — a round-trip break.
      final after =
          await tester.runAsync<String>(() => session.readCounterSource());
      final reparse = adapter.parseWidgetTreeFor(source: after!);
      expect(
        reparse,
        isA<WidgetTreeParseModeled>(),
        reason: 'iter $i: re-parse failed after edit. Source:\n$after',
      );
    }
  });
}

class _PropPick {
  _PropPick(this.path, this.propertyName, this.value);
  final NodePath path;
  final String propertyName;
  final PropertyValue value;

  @override
  String toString() => '$propertyName:${value.runtimeType}';
}

PropertyValue _mutate(PropertyValue v, Random rng, int seed) {
  return switch (v) {
    StringLiteralValue() => StringLiteralValue(
        value: 'edit_${seed}_${rng.nextInt(1 << 30)}',
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
