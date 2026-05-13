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

import 'package:test/test.dart';

// TODO(M1): import 'package:loom/loom.dart';

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

void main() {
  group('invariant 2 - no-op idempotence', () {
    test(
      'apply([], source) == source byte-for-byte',
      () {
        final source = _loadFixture('simple_widget.dart');
        expect(source, isNotEmpty);
        // TODO(M1): replace stub with:
        //   final model = WidgetTreeParser.parse(source);
        //   final edits = EditPlanner.plan(model, model);  // identity edit
        //   expect(applyEdits(source, edits), equals(source));
        fail('M1 not yet implemented');
      },
      skip: 'enable in M1: requires parser + identity emit',
    );
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
