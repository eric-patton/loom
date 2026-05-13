/// Round-trip property-test harness — the safety net for the Loom kernel.
///
/// Two invariants from PROJECT_SPEC.md North Star:
///   1. Round-trip stability: parse(apply(emit(edits), source)) is
///      AST-equivalent to the model after those edits.
///   2. No-op idempotence: apply([], source) == source byte-for-byte.
///
/// Both invariants are encoded as test groups below. Tests are skipped until
/// the kernel components they require land (M1 = parser, M2 = emission).
/// Flipping a skip on is a milestone deliverable — see the M1/M2 checklists
/// in DEVLOG.md.
library;

import 'dart:io';

import 'package:loom/loom.dart';
import 'package:test/test.dart';

/// How many randomized property-test iterations to run.
///
/// Local default: 100 (fast feedback). CI sets LOOM_PROPERTY_ITERATIONS=10000
/// to satisfy the global gate (PROJECT_SPEC.md Testing Strategy).
int get _propertyIterations {
  final raw = Platform.environment['LOOM_PROPERTY_ITERATIONS'];
  if (raw == null) {
    return 100;
  }
  return int.tryParse(raw) ?? 100;
}

String _loadFixture(String name) =>
    File('test/fixtures/$name').readAsStringSync();

/// The M1 fixture corpus. The no-op idempotence invariant runs once per
/// entry. Adding a fixture here is the only step needed to extend coverage.
const _m1Fixtures = <String>[
  // Hand-crafted.
  'simple_widget.dart',
  'nested_widget.dart',
  'no_trailing_commas.dart',
  'mixed_const.dart',
  'enum_and_bool.dart',
  // Real-world (flutter/website @ e927ec21, see DEVLOG fixture-corpus table).
  'real_world_layout_starter.dart',
  'real_world_widgets_intro_tutorial.dart',
  'real_world_cookbook_tabs.dart',
];

void main() {
  group('invariant 2 - no-op idempotence', () {
    for (final fixture in _m1Fixtures) {
      test('apply([], source) == source on $fixture', () {
        final source = _loadFixture(fixture);
        final model = parseWidgetTree(source);
        final result = applySourceEdits(source, const <SourceEdit>[]);
        expect(result, equals(source));
        // Guard against silently-empty parser: a no-op round-trip is
        // trivially true if the parser returned nothing, so verify the
        // parser actually built a model.
        expect(model.root.className, isNotEmpty);
      });
    }
  });

  group('invariant 1 - round-trip stability', () {
    test(
      'parse(apply(emit(M, edits), source)) is AST-equivalent to M edited',
      () {
        final iters = _propertyIterations;
        expect(iters, greaterThan(0));
        // TODO(M2): replace stub with glados property test:
        //   Glados<EditSequence>().test('round trip', (edits) {
        //     final model = WidgetTreeParser.parse(source);
        //     final edited = applyToModel(model, edits);
        //     final newSource = applyEdits(source, EditPlanner.plan(model, edited));
        //     final reparsed = WidgetTreeParser.parse(newSource);
        //     expect(AstEquivalence.compare(reparsed, edited), isTrue);
        //   });
        fail('M2 not yet implemented');
      },
      skip: 'enable in M2: requires emission + AST equivalence',
    );
  });
}
