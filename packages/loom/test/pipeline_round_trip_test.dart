/// Pipeline-tree round-trip tests (M6.2). Validates the same invariants
/// from PROJECT_SPEC for the third domain consumer of the kernel.
library;

import 'dart:io';

import 'package:loom/loom.dart';
import 'package:test/test.dart';

const _pipelineFixtures = <String>[
  'pipeline_simple.dart',
  'pipeline_with_branch.dart',
];

String _loadFixture(String name) =>
    File('test/fixtures/$name').readAsStringSync();

void main() {
  group('invariant 2 - no-op idempotence (pipelines)', () {
    for (final fixture in _pipelineFixtures) {
      test('apply([], source) == source on $fixture', () {
        final source = _loadFixture(fixture);
        final model = parsePipelineTree(source);
        final result = applySourceEdits(source, const <SourceEdit>[]);
        expect(result, equals(source));
        expect(model.root, isA<PipelineNode>());
        expect((model.root as PipelineNode).className, isNotEmpty);
      });
    }
  });

  group('property edit on pipeline node', () {
    test(
        'change ValidateInput.field "email" -> "username" preserves outside '
        'bytes', () {
      final source = _loadFixture('pipeline_simple.dart');
      final model = parsePipelineTree(source);
      final root = model.root as PipelineNode;
      final validate = root.childSlots['steps']!.first as PipelineNode;

      final oldField = validate.properties['field'] as StringLiteralValue;
      final newField = StringLiteralValue(
        value: 'username',
        usesDoubleQuotes: oldField.usesDoubleQuotes,
        span: oldField.span,
      );

      final edit = PipelineEditPlanner.propertyEdit(
        oldValue: oldField,
        newValue: newField,
      );
      final newSource = applySourceEdits(source, [edit]);

      final prefix = source.substring(0, oldField.span.offset);
      expect(newSource.substring(0, oldField.span.offset), equals(prefix));
      final suffix = source.substring(oldField.span.end);
      expect(
        newSource.substring(oldField.span.offset + edit.replacement.length),
        equals(suffix),
      );

      final reparsed = parsePipelineTree(newSource);
      final reparsedValidate = (reparsed.root as PipelineNode)
          .childSlots['steps']!
          .first as PipelineNode;
      expect(
        (reparsedValidate.properties['field'] as StringLiteralValue).value,
        equals('username'),
      );
    });
  });

  group('structural edit: insert pipeline step', () {
    test('insert a new Transform at index 1', () {
      final source = _loadFixture('pipeline_simple.dart');
      final model = parsePipelineTree(source);
      final root = model.root as PipelineNode;

      final newStep = PipelineNode(
        className: 'Transform',
        properties: {
          'name': const StringLiteralValue(
            value: 'sanitize',
            usesDoubleQuotes: false,
            span: SourceSpan(offset: 0, length: 0),
          ),
        },
        childSlots: const <String, List<ModelNode>>{},
        sourceSpan: const SourceSpan(offset: 0, length: 0),
        styleHints: const StyleHints(
          hasConst: false,
          hasNew: false,
          hasTrailingComma: false,
        ),
      );

      final edit = PipelineEditPlanner.insertChildEdit(
        parent: root,
        slotName: 'steps',
        index: 1,
        newChild: newStep,
        source: source,
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parsePipelineTree(newSource);
      final reparsedRoot = reparsed.root as PipelineNode;
      final steps = reparsedRoot.childSlots['steps']!;
      expect(steps, hasLength(4));
      expect((steps[1] as PipelineNode).className, equals('Transform'));
      expect(
        ((steps[1] as PipelineNode).properties['name'] as StringLiteralValue)
            .value,
        equals('sanitize'),
      );
    });
  });

  group('structural edit: move pipeline step', () {
    test('move first step to last position', () {
      final source = _loadFixture('pipeline_simple.dart');
      final model = parsePipelineTree(source);
      final root = model.root as PipelineNode;

      final edits = PipelineEditPlanner.moveChildEdits(
        parent: root,
        slotName: 'steps',
        from: 0,
        to: 2,
        source: source,
      );
      final newSource = applySourceEdits(source, edits);

      final reparsed = parsePipelineTree(newSource);
      final reparsedRoot = reparsed.root as PipelineNode;
      final steps = reparsedRoot.childSlots['steps']!;
      expect(steps, hasLength(3));
      // ValidateInput moved to index 2.
      expect((steps[2] as PipelineNode).className, equals('ValidateInput'));
    });
  });

  group('structural edit: remove step from branch', () {
    test('remove SendEmail from Branch.onTrue', () {
      final source = _loadFixture('pipeline_with_branch.dart');
      final model = parsePipelineTree(source);
      final root = model.root as PipelineNode;
      final branch = root.childSlots['steps']![2] as PipelineNode;

      final edit = PipelineEditPlanner.removeChildEdit(
        parent: branch,
        slotName: 'onTrue',
        index: 1,
        source: source,
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parsePipelineTree(newSource);
      final reparsedBranch = (reparsed.root as PipelineNode)
          .childSlots['steps']![2] as PipelineNode;
      final onTrue = reparsedBranch.childSlots['onTrue']!;
      expect(onTrue, hasLength(1));
      expect(
        (onTrue.first as PipelineNode).className,
        equals('SaveToDatabase'),
      );
    });
  });
}
