import 'dart:io';

import 'package:loom/loom.dart';
import 'package:test/test.dart';

void main() {
  group('parsePipelineTree on pipeline_simple.dart', () {
    late PipelineTreeModel model;
    late PipelineNode root;

    setUpAll(() {
      final source =
          File('test/fixtures/pipeline_simple.dart').readAsStringSync();
      model = parsePipelineTree(source);
      root = model.root as PipelineNode;
    });

    test('parses with no diagnostics', () {
      expect(model.diagnostics, isEmpty);
    });

    test('root is Pipeline with three steps', () {
      expect(root.className, equals('Pipeline'));
      final steps = root.childSlots['steps'];
      expect(steps, hasLength(3));
    });

    test('name property captured as string literal', () {
      final name = root.properties['name'];
      expect(name, isA<StringLiteralValue>());
      expect((name! as StringLiteralValue).value, equals('simple'));
    });

    test('step kinds and properties captured', () {
      final steps = root.childSlots['steps']!;
      final validate = steps[0] as PipelineNode;
      expect(validate.className, equals('ValidateInput'));
      expect(
        (validate.properties['field'] as StringLiteralValue).value,
        equals('email'),
      );
      expect(
        (validate.properties['required'] as BoolLiteralValue).value,
        isTrue,
      );

      final transform = steps[1] as PipelineNode;
      expect(transform.className, equals('Transform'));
      expect(
        (transform.properties['name'] as StringLiteralValue).value,
        equals('normalizeEmail'),
      );

      final save = steps[2] as PipelineNode;
      expect(save.className, equals('SaveToDatabase'));
      expect(
        (save.properties['table'] as StringLiteralValue).value,
        equals('users'),
      );
    });
  });

  group('parsePipelineTree on pipeline_with_branch.dart', () {
    late PipelineTreeModel model;
    late PipelineNode root;

    setUpAll(() {
      final source =
          File('test/fixtures/pipeline_with_branch.dart').readAsStringSync();
      model = parsePipelineTree(source);
      root = model.root as PipelineNode;
    });

    test('parses with no diagnostics', () {
      expect(model.diagnostics, isEmpty);
    });

    test('Branch has two list slots (onTrue, onFalse)', () {
      final steps = root.childSlots['steps']!;
      // Index 2 is the Branch (after validate + transform).
      final branch = steps[2] as PipelineNode;
      expect(branch.className, equals('Branch'));

      final onTrue = branch.childSlots['onTrue'];
      expect(onTrue, hasLength(2));
      expect((onTrue![0] as PipelineNode).className, equals('SaveToDatabase'));
      expect((onTrue[1] as PipelineNode).className, equals('SendEmail'));

      final onFalse = branch.childSlots['onFalse'];
      expect(onFalse, hasLength(1));
      expect((onFalse![0] as PipelineNode).className, equals('LogError'));
    });

    test('Branch list slots each have list-style hints captured', () {
      final branch = root.childSlots['steps']![2] as PipelineNode;
      expect(branch.childSlotStyles['onTrue'], isNotNull);
      expect(branch.childSlotStyles['onFalse'], isNotNull);
      expect(branch.childSlotStyles['onTrue']!.hasTrailingComma, isTrue);
      expect(branch.childSlotStyles['onTrue']!.isMultiLine, isTrue);
    });

    test('LogError carries level + message string properties', () {
      final branch = root.childSlots['steps']![2] as PipelineNode;
      final logError = branch.childSlots['onFalse']!.first as PipelineNode;
      expect(
        (logError.properties['level'] as StringLiteralValue).value,
        equals('warn'),
      );
      expect(
        (logError.properties['message'] as StringLiteralValue).value,
        equals('Invalid email'),
      );
    });
  });

  group('parsePipelineTree rejection', () {
    test('throws on a widget file', () {
      final source =
          File('test/fixtures/simple_widget.dart').readAsStringSync();
      expect(() => parsePipelineTree(source), throwsA(isA<ParseException>()));
    });

    test('throws on a route file', () {
      final source = File('test/fixtures/route_simple.dart').readAsStringSync();
      expect(() => parsePipelineTree(source), throwsA(isA<ParseException>()));
    });
  });

  // ----------------------------------------------------------------
  // PipelineTreeNavigation — node_path API extended to pipeline trees.
  // ----------------------------------------------------------------
  group('PipelineTreeNavigation', () {
    late PipelineTreeModel model;

    setUpAll(() {
      final source =
          File('test/fixtures/pipeline_simple.dart').readAsStringSync();
      model = parsePipelineTree(source);
    });

    test('nodeAt(empty) returns the Pipeline root', () {
      final got = model.nodeAt(const <NodePathSegment>[]);
      expect(got, isA<PipelineNode>());
      expect((got! as PipelineNode).className, equals('Pipeline'));
    });

    test('nodeAt descends into a step', () {
      final got = model.nodeAt(const [(slot: 'steps', index: 0)]);
      expect(got, isA<PipelineNode>());
      expect((got! as PipelineNode).className, equals('ValidateInput'));
    });

    test('withProperty preserves PipelineNode subtype on rebuild', () {
      final updated = model.withProperty(
        const <NodePathSegment>[],
        'name',
        const StringLiteralValue(
          value: 'renamed',
          span: SourceSpan(offset: 0, length: 0),
        ),
      );
      expect(updated.root, isA<PipelineNode>());
      final newRoot = updated.root as PipelineNode;
      final name = newRoot.properties['name']! as StringLiteralValue;
      expect(name.value, equals('renamed'));
      // steps slot unchanged.
      expect(newRoot.childSlots['steps']!.length,
          equals((model.root as PipelineNode).childSlots['steps']!.length));
    });

    test('walk traverses all PipelineNodes', () {
      final entries = model.walk();
      final names = entries
          .map((e) => e.node)
          .whereType<PipelineNode>()
          .map((p) => p.className)
          .toList();
      // Original fixture has Pipeline + ValidateInput + Transform + LogError.
      expect(names, containsAll(['Pipeline', 'ValidateInput']));
    });
  });
}
