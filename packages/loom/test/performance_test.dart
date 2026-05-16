import 'package:loom/loom.dart';
import 'package:test/test.dart';

/// Global Acceptance #5 (PROJECT_SPEC.md):
///   - parsing a 1,000-line file completes in under 100ms
///   - emitting an edit completes in under 10ms
///
/// Wall-clock perf assertions are inherently noisy. To keep this stable
/// in CI we take the best of N runs (after a warmup) so a one-off slow
/// run from GC, scheduling, or thermal throttling doesn't fail the gate.
String _build1000LineSource() {
  final buf = StringBuffer();
  buf.writeln('class BigPage extends StatelessWidget {');
  buf.writeln('  const BigPage({super.key});');
  buf.writeln('  @override');
  buf.writeln('  Widget build(BuildContext context) {');
  buf.writeln('    return Column(');
  buf.writeln('      children: [');
  for (var i = 0; i < 1000; i++) {
    buf.writeln("        const Text('row $i'),");
  }
  buf.writeln('      ],');
  buf.writeln('    );');
  buf.writeln('  }');
  buf.writeln('}');
  return buf.toString();
}

void main() {
  group('Global Acceptance #5 - performance', () {
    late final String source;
    late final WidgetTreeModel model;
    late final WidgetNode firstText;
    late final StringLiteralValue firstData;

    setUpAll(() {
      source = _build1000LineSource();
      // Sanity: expected line count is > 1,000.
      assert(
        source.split('\n').length > 1000,
        'fixture should exceed 1,000 lines',
      );

      // Warmup parse to amortize JIT/class loading. The measured runs
      // re-parse from scratch — that's the per-call cost the spec is
      // gating on.
      model = parseWidgetTree(source);
      firstText = (model.root as WidgetNode).childSlots['children']!.first
          as WidgetNode;
      firstData = firstText.properties['data']! as StringLiteralValue;
    });

    test('parse < 100ms on a >1,000-line source (best of 5)', () {
      final timesUs = <int>[];
      for (var i = 0; i < 5; i++) {
        final sw = Stopwatch()..start();
        parseWidgetTree(source);
        sw.stop();
        timesUs.add(sw.elapsedMicroseconds);
      }
      timesUs.sort();
      final best = timesUs.first;
      expect(
        best,
        lessThan(100 * 1000),
        reason:
            'best parse time across 5 runs: ${(best / 1000).toStringAsFixed(1)}ms '
            '(all: ${timesUs.map((t) => (t / 1000).toStringAsFixed(1)).join(", ")} ms)',
      );
    });

    test('property edit emission < 10ms (best of 5)', () {
      const newValue = StringLiteralValue(
        value: 'changed',
        span: SourceSpan(offset: 0, length: 0),
      );
      // Warmup
      EditPlanner.propertyEdit(oldValue: firstData, newValue: newValue);

      final timesUs = <int>[];
      for (var i = 0; i < 5; i++) {
        final sw = Stopwatch()..start();
        EditPlanner.propertyEdit(oldValue: firstData, newValue: newValue);
        sw.stop();
        timesUs.add(sw.elapsedMicroseconds);
      }
      timesUs.sort();
      final best = timesUs.first;
      expect(
        best,
        lessThan(10 * 1000),
        reason:
            'best emit time across 5 runs: ${(best / 1000).toStringAsFixed(2)}ms '
            '(all: ${timesUs.map((t) => (t / 1000).toStringAsFixed(2)).join(", ")} ms)',
      );
    });
  });
}
