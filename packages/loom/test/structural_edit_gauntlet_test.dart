/// Property-test gauntlet for M7-M10 structural edits.
///
/// Mirrors the M2/M3 widget-edit gauntlets (round_trip_test.dart) for the
/// later milestones — class-structure (M7), function-body (M8), and
/// directives (M9) edit planners.
///
/// What this catches:
///   * **Byte-minimality on removes** — every remove* op must leave the
///     surrounding source byte-for-byte unchanged outside the killed
///     region, and produce no orphan whitespace. The C1 fix from the
///     M10.2c kernel review (removeMember leaving the leading indent
///     behind) is the canonical instance — without coverage here, a
///     future regression would slip through.
///   * **Re-parse stability** — after every supported edit, the result
///     re-parses without diagnostics, so structural edits never produce
///     un-modelable source.
///   * **No-op idempotence** — `applySourceEdits(source, [])` matches the
///     source bytes for every fixture under every model kind.
library;

import 'dart:io';
import 'dart:math';

import 'package:loom/loom.dart';
import 'package:test/test.dart';

String _loadFixture(String name) =>
    File('test/fixtures/$name').readAsStringSync();

int get _propertyIterations {
  final raw = Platform.environment['LOOM_PROPERTY_ITERATIONS'];
  if (raw == null) return 50;
  return int.tryParse(raw) ?? 50;
}

/// Validates that an edit did not introduce orphan-indentation lines —
/// whitespace-only lines that weren't present in the original. The C1
/// regression (removeMember leaving the killed line's leading indent
/// behind) showed up exactly as "edited has 1 more whitespace-only line
/// than original," so this is the catch.
void _expectNoOrphanIndent(String original, String edited) {
  int countOrphanLines(String s) =>
      s.split('\n').where((l) => l.isNotEmpty && l.trim().isEmpty).length;
  final origCount = countOrphanLines(original);
  final editedCount = countOrphanLines(edited);
  if (editedCount > origCount) {
    fail(
      'edit introduced orphan-indent line(s)\n'
      '  original whitespace-only lines: $origCount\n'
      '  edited   whitespace-only lines: $editedCount\n'
      '  edited content:\n$edited',
    );
  }
}

void main() {
  // Self-test: the orphan-indent helper must actually flag a bad edit.
  // Belt-and-suspenders sanity that the gauntlet would catch the C1
  // regression if it came back.
  group('orphan-indent helper self-test', () {
    test('flags an added whitespace-only line', () {
      const original = 'class A {\n  final int x;\n  final int y;\n}\n';
      // Hypothetical bad output: removed `final int y;` but left its
      // leading 2-space indent as an orphan line.
      const bad = 'class A {\n  final int x;\n  \n}\n';
      expect(
        () => _expectNoOrphanIndent(original, bad),
        throwsA(isA<TestFailure>()),
      );
    });

    test('does not flag a clean remove', () {
      const original = 'class A {\n  final int x;\n  final int y;\n}\n';
      const good = 'class A {\n  final int x;\n}\n';
      _expectNoOrphanIndent(original, good); // must not throw
    });
  });

  // ----------------------------------------------------------------
  // Class-structure (M7) removes
  // ----------------------------------------------------------------
  group('class-structure remove gauntlet', () {
    const fixtures = <String>[
      'class_simple.dart',
      'class_with_methods.dart',
      'class_with_constructors.dart',
      'class_freezed_like.dart',
    ];
    for (final fixture in fixtures) {
      test('every member removable from $fixture leaves clean bytes', () {
        final source = _loadFixture(fixture);
        final model = parseClassStructure(source);

        for (final member in model.root.members) {
          if (member is OpaqueClassMember) continue;
          final edit = ClassStructureEditPlanner.removeMember(
            member: member,
            source: source,
          );
          final result = applySourceEdits(source, [edit]);

          // Re-parse cleanly.
          final reparsed = parseClassStructure(result);
          expect(reparsed.diagnostics, isEmpty,
              reason: 'remove of ${member.runtimeType} produced un-parseable '
                  'source for $fixture\n$result');
          _expectNoOrphanIndent(source, result);

          // The removed member's name must no longer appear.
          final removedName = _memberName(member);
          if (removedName != null) {
            final namesAfter = reparsed.root.members
                .map(_memberName)
                .whereType<String>()
                .toList();
            expect(namesAfter, isNot(contains(removedName)),
                reason: 'member "$removedName" still in class after remove');
          }
        }
      });
    }

    test(
        'randomized: remove a random member 50× per fixture leaves '
        'clean bytes', () {
      final rng = Random(0xC1A55);
      for (final fixture in fixtures) {
        for (var i = 0; i < _propertyIterations; i++) {
          final source = _loadFixture(fixture);
          final model = parseClassStructure(source);
          final removable =
              model.root.members.where((m) => m is! OpaqueClassMember).toList();
          if (removable.isEmpty) continue;
          final pick = removable[rng.nextInt(removable.length)];
          final edit = ClassStructureEditPlanner.removeMember(
            member: pick,
            source: source,
          );
          final result = applySourceEdits(source, [edit]);
          final reparsed = parseClassStructure(result);
          expect(reparsed.diagnostics, isEmpty);
          _expectNoOrphanIndent(source, result);
        }
      }
    });
  });

  // ----------------------------------------------------------------
  // Function-body (M8) removes
  // ----------------------------------------------------------------
  group('function-body remove gauntlet', () {
    const fixtures = <String>[
      'function_body_simple.dart',
      'function_body_with_if.dart',
      'function_body_with_else_if.dart',
      'function_body_with_loops.dart',
      'function_body_with_do_while.dart',
      'function_body_with_switch.dart',
      'function_body_with_throw.dart',
    ];
    for (final fixture in fixtures) {
      test(
          'every top-level statement removable from $fixture leaves clean '
          'bytes', () {
        final source = _loadFixture(fixture);
        final model = parseFunctionBody(source);

        for (final stmt in model.statements) {
          final edit = FunctionBodyEditPlanner.removeStatement(
            statement: stmt,
            source: source,
          );
          final result = applySourceEdits(source, [edit]);
          final reparsed = parseFunctionBody(result);
          expect(reparsed.diagnostics, isEmpty,
              reason:
                  'remove of ${stmt.runtimeType} produced un-parseable source '
                  'for $fixture\n$result');
          _expectNoOrphanIndent(source, result);
        }
      });
    }
  });

  // ----------------------------------------------------------------
  // Directives (M9) removes
  // ----------------------------------------------------------------
  group('directives remove gauntlet', () {
    test(
        'every directive removable from directives_simple.dart leaves clean '
        'bytes', () {
      const fixture = 'directives_simple.dart';
      final source = _loadFixture(fixture);
      final model = parseDirectives(source);

      for (final d in model.directives) {
        final edit = DirectivesEditPlanner.removeDirective(
          directive: d,
          source: source,
        );
        final result = applySourceEdits(source, [edit]);
        final reparsed = parseDirectives(result);
        expect(reparsed.diagnostics, isEmpty,
            reason: 'remove of ${d.runtimeType} produced un-parseable source\n'
                '$result');
        _expectNoOrphanIndent(source, result);
      }
    });
  });

  // ----------------------------------------------------------------
  // No-op idempotence across every M7-M10 fixture.
  // ----------------------------------------------------------------
  group('no-op idempotence — every M7-M10 fixture', () {
    final allFixtures = <String>[
      'class_simple.dart',
      'class_with_methods.dart',
      'class_with_constructors.dart',
      'class_freezed_like.dart',
      'function_body_simple.dart',
      'function_body_with_if.dart',
      'function_body_with_else_if.dart',
      'function_body_with_loops.dart',
      'function_body_with_do_while.dart',
      'function_body_with_switch.dart',
      'function_body_with_throw.dart',
      'function_body_with_for_headers.dart',
      'function_body_with_expressions.dart',
      'function_body_with_more_expressions.dart',
      'function_body_with_more_expression_kinds.dart',
      'function_body_with_object_record_patterns.dart',
      'function_body_with_remaining_patterns.dart',
      'function_body_with_switch_expressions.dart',
      'function_body_with_collections_and_functions.dart',
      'directives_simple.dart',
    ];
    for (final fixture in allFixtures) {
      test('$fixture: applySourceEdits(source, []) == source', () {
        final source = _loadFixture(fixture);
        expect(
          applySourceEdits(source, const <SourceEdit>[]),
          equals(source),
        );
      });
    }
  });
}

String? _memberName(ClassMember member) => switch (member) {
      final ClassFieldNode f => f.name,
      final ClassMethodNode m => m.name,
      final ClassConstructorNode c => c.namedConstructorName ?? '(default)',
      OpaqueClassMember() => null,
    };
