/// Round-trip property-test harness — the safety net for the Loom kernel.
///
/// Two invariants from PROJECT_SPEC.md North Star:
///   1. Round-trip stability: parse(apply(emit(edits), source)) is
///      structurally equivalent (Q3) to the model after those edits.
///   2. No-op idempotence: apply([], source) == source byte-for-byte.
///
/// Both invariants are encoded as test groups below.
library;

import 'dart:io';
import 'dart:math';

import 'package:loom/loom.dart';
import 'package:test/test.dart';

/// How many randomized iterations to run *per fixture* for the invariant-1
/// property and structural tests.
///
/// Local default: 100 per fixture (~1,000 total across the corpus). CI
/// sets `LOOM_PROPERTY_ITERATIONS=10000`, matching the spec's
/// "10,000 iterations per fixture per run" gate (PROJECT_SPEC.md
/// "Testing Strategy" / Global Acceptance #2).
int get _propertyIterations {
  final raw = Platform.environment['LOOM_PROPERTY_ITERATIONS'];
  if (raw == null) {
    return 100;
  }
  return int.tryParse(raw) ?? 100;
}

String _loadFixture(String name) =>
    File('test/fixtures/$name').readAsStringSync();

/// The M1 fixture corpus.
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
  // M4: exercises opaque handling (closure, BoxDecoration, EdgeInsets.symmetric).
  'real_world_opaque_mybutton.dart',
  // M5: exercises in-class helper-method following.
  'helper_methods.dart',
];

class _CachedFixture {
  _CachedFixture(this.name, this.source, this.model);

  final String name;
  final String source;
  final WidgetTreeModel model;
}

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

  group('invariant 1 - round-trip stability under property edits', () {
    late final List<_CachedFixture> fixtures;

    setUpAll(() {
      fixtures = [
        for (final name in _m1Fixtures)
          () {
            final source = _loadFixture(name);
            return _CachedFixture(name, source, parseWidgetTree(source));
          }(),
      ];
    });

    test('random property edits round-trip to equivalent models', () {
      // Deterministic seed so CI failures reproduce locally.
      final rng = Random(0x10AD);
      final iterations = _propertyIterations;
      var totalEdits = 0;

      // Iterate PER FIXTURE so every file gets `iterations` random edits.
      // (Spec: "10,000 iterations per fixture per run".)
      for (final fixture in fixtures) {
        final targets = fixture.model
            .walk()
            .where((entry) => entry.node is WidgetNode)
            .map(
              (entry) => (path: entry.path, node: entry.node as WidgetNode),
            )
            .where(
              (entry) => entry.node.properties.values.any(
                (v) => v is! OpaquePropertyValue,
              ),
            )
            .toList();
        if (targets.isEmpty) {
          continue;
        }

        for (var i = 0; i < iterations; i++) {
          final target = targets[rng.nextInt(targets.length)];
          // Exclude opaque properties from random selection.
          final editableNames = target.node.properties.entries
              .where((e) => e.value is! OpaquePropertyValue)
              .map((e) => e.key)
              .toList();
          if (editableNames.isEmpty) {
            continue;
          }
          final propName = editableNames[rng.nextInt(editableNames.length)];
          final oldValue = target.node.properties[propName]!;
          final newValue = _generateValue(rng);

          final expected = fixture.model.withProperty(
            target.path,
            propName,
            newValue,
          );

          final edit = EditPlanner.propertyEdit(
            oldValue: oldValue,
            newValue: newValue,
          );
          final newSource = applySourceEdits(fixture.source, [edit]);

          final reparsed = parseWidgetTree(newSource);

          final reason = 'iteration $i: fixture=${fixture.name} '
              'path=${target.path} prop=$propName '
              'old=$oldValue new=$newValue';

          // Q3 invariant: structurally equivalent.
          expect(
            StructuralEquivalence.equal(reparsed, expected),
            isTrue,
            reason: reason,
          );

          // Minimal-diff invariant: prefix and suffix unchanged.
          final prefixOld = fixture.source.substring(0, oldValue.span.offset);
          final prefixNew = newSource.substring(0, oldValue.span.offset);
          expect(prefixNew, equals(prefixOld), reason: 'prefix; $reason');

          final suffixOld = fixture.source.substring(
            oldValue.span.offset + oldValue.span.length,
          );
          final suffixNew = newSource.substring(
            oldValue.span.offset + edit.replacement.length,
          );
          expect(suffixNew, equals(suffixOld), reason: 'suffix; $reason');

          totalEdits++;
        }
      }

      expect(
        totalEdits,
        greaterThan(0),
        reason: 'no editable property was found across the entire corpus',
      );
    }, timeout: const Timeout(Duration(minutes: 10)));
  });

  group('invariant 1 - round-trip stability under structural edits', () {
    late final List<_CachedFixture> fixtures;

    setUpAll(() {
      fixtures = [
        for (final name in _m1Fixtures)
          () {
            final source = _loadFixture(name);
            return _CachedFixture(name, source, parseWidgetTree(source));
          }(),
      ];
    });

    test('1-10 mixed insert/remove/move sequences round-trip', () {
      final rng = Random(0x5704C7);
      final iterations = _propertyIterations;
      var totalSequences = 0;
      var totalEditsPerformed = 0;

      // Iterate PER FIXTURE so every file gets `iterations` random
      // edit sequences (each up to 10 mixed structural edits).
      for (final fixture in fixtures) {
        for (var i = 0; i < iterations; i++) {
          var currentSource = fixture.source;
          var currentModel = fixture.model;

          final sequenceLength = 1 + rng.nextInt(10);
          var stepsRun = 0;

          for (var step = 0; step < sequenceLength; step++) {
            final targets = _listSlotTargets(currentModel);
            if (targets.isEmpty) {
              break;
            }
            final target = targets[rng.nextInt(targets.length)];
            final parent =
                currentModel.nodeAt(target.parentPath)! as WidgetNode;
            final children =
                parent.childSlots[target.slot] ?? const <ModelNode>[];

            final ops = <String>[
              'insert',
              if (children.isNotEmpty) 'remove',
              if (children.length >= 2) 'move',
            ];
            final op = ops[rng.nextInt(ops.length)];

            final reason = 'iter $i step $step: fixture=${fixture.name} '
                'path=${target.parentPath} slot=${target.slot} op=$op '
                '(children.length=${children.length})';

            WidgetTreeModel expected;
            List<SourceEdit> edits;

            switch (op) {
              case 'insert':
                final index = rng.nextInt(children.length + 1);
                final newChild = _generateChild(rng);
                expected = currentModel.insertChild(
                  target.parentPath,
                  target.slot,
                  index,
                  newChild,
                );
                edits = <SourceEdit>[
                  EditPlanner.insertChildEdit(
                    parent: parent,
                    slotName: target.slot,
                    index: index,
                    newChild: newChild,
                    source: currentSource,
                  ),
                ];
              case 'remove':
                final index = rng.nextInt(children.length);
                expected = currentModel.removeChild(
                  target.parentPath,
                  target.slot,
                  index,
                );
                edits = <SourceEdit>[
                  EditPlanner.removeChildEdit(
                    parent: parent,
                    slotName: target.slot,
                    index: index,
                    source: currentSource,
                  ),
                ];
              case 'move':
                final from = rng.nextInt(children.length);
                var to = rng.nextInt(children.length);
                if (from == to) {
                  to = (to + 1) % children.length;
                }
                expected = currentModel.moveChild(
                  target.parentPath,
                  target.slot,
                  from,
                  to,
                );
                edits = EditPlanner.moveChildEdits(
                  parent: parent,
                  slotName: target.slot,
                  from: from,
                  to: to,
                  source: currentSource,
                );
              default:
                throw StateError('unknown op');
            }

            final newSource = applySourceEdits(currentSource, edits);
            final reparsed = parseWidgetTree(newSource);
            expect(
              StructuralEquivalence.equal(reparsed, expected),
              isTrue,
              reason: reason,
            );

            currentSource = newSource;
            currentModel = reparsed;
            stepsRun++;
            totalEditsPerformed++;
          }

          if (stepsRun > 0) {
            totalSequences++;
          }
        }
      }

      expect(
        totalSequences,
        greaterThan(0),
        reason: 'no structural edits ran across the corpus',
      );
      expect(
        totalEditsPerformed,
        greaterThan(iterations ~/ 2),
        reason: 'most iterations produced 0 edits; check fixture coverage',
      );
    }, timeout: const Timeout(Duration(minutes: 10)));
  });
}

List<({NodePath parentPath, String slot})> _listSlotTargets(
  WidgetTreeModel model,
) {
  final out = <({NodePath parentPath, String slot})>[];
  for (final entry in model.walk()) {
    final node = entry.node;
    if (node is! WidgetNode) {
      continue;
    }
    for (final slot in node.childSlotStyles.keys) {
      out.add((parentPath: entry.path, slot: slot));
    }
  }
  return out;
}

WidgetNode _generateChild(Random rng) {
  // 1/3 chance of a single Text; 1/3 chance of a Padding wrapping one
  // Text; 1/3 chance of a Column with two Text children. Exercises both
  // single- and list-shaped child slots in inserted widgets.
  const span = SourceSpan(offset: 0, length: 0);
  final shape = rng.nextInt(3);
  switch (shape) {
    case 0:
      return _genText(rng);
    case 1:
      return WidgetNode(
        className: 'Padding',
        properties: {
          'padding': EdgeInsetsAllValue(
            amount: rng.nextInt(20),
            amountIsDouble: rng.nextBool(),
            span: span,
          ),
        },
        childSlots: {
          'child': [_genText(rng)],
        },
        sourceSpan: span,
        styleHints: const StyleHints(),
      );
    default:
      return WidgetNode(
        className: 'Column',
        properties: const {},
        childSlots: {
          'children': [_genText(rng), _genText(rng)],
        },
        // Must match the WidgetSerializer output's resulting style on
        // reparse: a serialized Column emits `Column(children: [a, b])`
        // which reparses as single-line, no trailing comma.
        childSlotStyles: const {
          'children': ListSlotStyle(
            bracketsSpan: SourceSpan(offset: 0, length: 0),
            hasTrailingComma: false,
            isMultiLine: false,
          ),
        },
        sourceSpan: span,
        styleHints: const StyleHints(),
      );
  }
}

WidgetNode _genText(Random rng) {
  const span = SourceSpan(offset: 0, length: 0);
  return WidgetNode(
    className: 'Text',
    properties: {
      'data': StringLiteralValue(
        value: _randomString(rng),
        usesDoubleQuotes: rng.nextBool(),
        span: span,
      ),
    },
    childSlots: const {},
    sourceSpan: span,
    styleHints: const StyleHints(),
  );
}

const _generatorSpan = SourceSpan(offset: 0, length: 0);
// Includes Dart metacharacters that exercise the serializer's escape
// paths: backslash, single quote, double quote, dollar, newline, tab,
// and forward-slash (which doesn't need escaping but tests separator
// detection logic).
const _stringChars = "abcdefghijklmnopqrstuvwxyz0123456789 \$\\'\"\n\t/";

PropertyValue _generateValue(Random rng) {
  final variant = rng.nextInt(8);
  switch (variant) {
    case 0:
      return StringLiteralValue(
        value: _randomString(rng),
        usesDoubleQuotes: rng.nextBool(),
        span: _generatorSpan,
      );
    case 1:
      return NumLiteralValue(
        value: rng.nextInt(1000),
        isDouble: false,
        span: _generatorSpan,
      );
    case 2:
      return NumLiteralValue(
        value: rng.nextDouble() * 100,
        isDouble: true,
        span: _generatorSpan,
      );
    case 3:
      return BoolLiteralValue(value: rng.nextBool(), span: _generatorSpan);
    case 4:
      return const NullLiteralValue(span: _generatorSpan);
    case 5:
      return EdgeInsetsAllValue(
        amount: rng.nextInt(50),
        amountIsDouble: rng.nextBool(),
        span: _generatorSpan,
      );
    case 6:
      return ColorValue(
        argbValue: 0xFF000000 | rng.nextInt(0x1000000),
        span: _generatorSpan,
      );
    default:
      return EnumReferenceValue(
        typeName: 'GenType${rng.nextInt(10)}',
        memberName: 'member${rng.nextInt(10)}',
        span: _generatorSpan,
      );
  }
}

String _randomString(Random rng) {
  final length = rng.nextInt(20);
  return String.fromCharCodes(
    List<int>.generate(
      length,
      (_) => _stringChars.codeUnitAt(rng.nextInt(_stringChars.length)),
    ),
  );
}
