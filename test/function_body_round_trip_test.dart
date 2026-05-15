/// Function-body round-trip tests (M8.0a).
library;

import 'dart:io';

import 'package:loom/loom.dart';
import 'package:test/test.dart';

String _loadFixture(String name) =>
    File('test/fixtures/$name').readAsStringSync();

void main() {
  group('invariant 2 - no-op idempotence (function body)', () {
    test('apply([], source) == source on function_body_simple.dart', () {
      final source = _loadFixture('function_body_simple.dart');
      final body = parseFunctionBody(source);
      final result = applySourceEdits(source, const <SourceEdit>[]);
      expect(result, equals(source));
      expect(body.statements, isNotEmpty);
    });
  });

  group('renameDeclaredVariable', () {
    test('renames "normalized" -> "normalizedEmail"', () {
      final source = _loadFixture('function_body_simple.dart');
      final body = parseFunctionBody(source);
      final firstVar = body.statements[0] as VariableDeclarationStatementNode;
      final normalized = firstVar.variables.first;

      final edit = FunctionBodyEditPlanner.renameDeclaredVariable(
        variable: normalized,
        newName: 'normalizedEmail',
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseFunctionBody(newSource);
      final reparsedVar =
          reparsed.statements[0] as VariableDeclarationStatementNode;
      expect(reparsedVar.variables.first.name, equals('normalizedEmail'));
    });
  });

  group('changeVariableInitializer', () {
    test('changes initializer "nextId()" -> "generateId()"', () {
      final source = _loadFixture('function_body_simple.dart');
      final body = parseFunctionBody(source);
      // Second var declaration: `final id = nextId();`
      final idStmt = body.statements[1] as VariableDeclarationStatementNode;
      final idVar = idStmt.variables.first;

      final edit = FunctionBodyEditPlanner.changeVariableInitializer(
        variable: idVar,
        newInitializerSource: 'generateId()',
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseFunctionBody(newSource);
      final reparsedId =
          (reparsed.statements[1] as VariableDeclarationStatementNode)
              .variables
              .first;
      expect(reparsedId.initializerSource, equals('generateId()'));
    });
  });

  group('changeReturnExpression', () {
    test('changes `return id;` to `return id + 1;`', () {
      final source = _loadFixture('function_body_simple.dart');
      final body = parseFunctionBody(source);
      final ret = body.statements[4] as ReturnStatementNode;

      final edit = FunctionBodyEditPlanner.changeReturnExpression(
        statement: ret,
        newExpressionSource: 'id + 1',
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseFunctionBody(newSource);
      final reparsedRet = reparsed.statements[4] as ReturnStatementNode;
      expect(reparsedRet.expressionSource, equals('id + 1'));
    });
  });

  group('addStatement', () {
    test('inserts a new expression statement before the return', () {
      final source = _loadFixture('function_body_simple.dart');
      final body = parseFunctionBody(source);

      // body has 5 statements; index 4 is the return. Insert at 4 to
      // place the new statement BEFORE return.
      final edit = FunctionBodyEditPlanner.addStatement(
        block: body.body,
        index: 4,
        newStatementSource: 'log(\'success: \$id\');',
        source: source,
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseFunctionBody(newSource);
      expect(reparsed.statements, hasLength(6));
      // The 5th statement (index 4) should now be the new log() call.
      final inserted = reparsed.statements[4] as ExpressionStatementNode;
      expect(inserted.expressionSource, startsWith('log('));
      // The 6th is the return.
      expect(reparsed.statements[5], isA<ReturnStatementNode>());
    });

    test('appends a statement at end of body', () {
      final source = _loadFixture('function_body_simple.dart');
      final body = parseFunctionBody(source);
      final originalCount = body.statements.length;

      final edit = FunctionBodyEditPlanner.addStatement(
        block: body.body,
        index: originalCount,
        newStatementSource: 'audit(id);',
        source: source,
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseFunctionBody(newSource);
      expect(reparsed.statements, hasLength(originalCount + 1));
      expect(reparsed.statements.last, isA<ExpressionStatementNode>());
    });
  });

  group('removeStatement', () {
    test('removes the second log() call (third statement)', () {
      final source = _loadFixture('function_body_simple.dart');
      final body = parseFunctionBody(source);
      final logCall = body.statements[2];
      expect(logCall, isA<ExpressionStatementNode>());

      final edit = FunctionBodyEditPlanner.removeStatement(
        statement: logCall,
        source: source,
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseFunctionBody(newSource);
      expect(reparsed.statements, hasLength(4));
      // The saveUser call is now at index 2.
      final saveStmt = reparsed.statements[2] as ExpressionStatementNode;
      expect(saveStmt.expressionSource, startsWith('saveUser('));
    });
  });

  group('if-statement edits (M8.0b)', () {
    test('idempotence on function_body_with_if.dart', () {
      final source = _loadFixture('function_body_with_if.dart');
      final body = parseFunctionBody(source);
      final result = applySourceEdits(source, const <SourceEdit>[]);
      expect(result, equals(source));
      expect(body.statements, isNotEmpty);
    });

    test('changeIfCondition rewrites the condition expression', () {
      final source = _loadFixture('function_body_with_if.dart');
      final body = parseFunctionBody(source);
      final ifStmt = body.statements[2] as IfStatementNode;
      expect(ifStmt.conditionSource, equals('clamped >= 90'));

      final edit = FunctionBodyEditPlanner.changeIfCondition(
        statement: ifStmt,
        newConditionSource: 'clamped == 100',
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseFunctionBody(newSource);
      final reparsedIf = reparsed.statements[2] as IfStatementNode;
      expect(reparsedIf.conditionSource, equals('clamped == 100'));
    });

    test('addStatement into the then-block (recursive)', () {
      final source = _loadFixture('function_body_with_if.dart');
      final body = parseFunctionBody(source);
      final ifStmt = body.statements[2] as IfStatementNode;
      expect(ifStmt.thenBlock.statements, hasLength(2));

      final edit = FunctionBodyEditPlanner.addStatement(
        block: ifStmt.thenBlock,
        index: 0,
        newStatementSource: 'audit(clamped);',
        source: source,
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseFunctionBody(newSource);
      final reparsedIf = reparsed.statements[2] as IfStatementNode;
      expect(reparsedIf.thenBlock.statements, hasLength(3));
      final first =
          reparsedIf.thenBlock.statements.first as ExpressionStatementNode;
      expect(first.expressionSource, equals('audit(clamped)'));
    });

    test('removeStatement from the else-block', () {
      // Add another statement to else, then remove it.
      final source = _loadFixture('function_body_with_if.dart');
      final body = parseFunctionBody(source);
      final ifStmt = body.statements[2] as IfStatementNode;

      // First, insert a logging call into the else block (index 0).
      final addEdit = FunctionBodyEditPlanner.addStatement(
        block: ifStmt.elseBlock!,
        index: 0,
        newStatementSource: 'log(\'lower path\');',
        source: source,
      );
      final intermediate = applySourceEdits(source, [addEdit]);

      // Re-parse, remove the log call.
      final intermediateBody = parseFunctionBody(intermediate);
      final intermediateIf = intermediateBody.statements[2] as IfStatementNode;
      expect(intermediateIf.elseBlock!.statements, hasLength(2));

      final logStmt = intermediateIf.elseBlock!.statements.first;
      final removeEdit = FunctionBodyEditPlanner.removeStatement(
        statement: logStmt,
        source: intermediate,
      );
      final finalSource = applySourceEdits(intermediate, [removeEdit]);

      final finalBody = parseFunctionBody(finalSource);
      final finalIf = finalBody.statements[2] as IfStatementNode;
      expect(finalIf.elseBlock!.statements, hasLength(1));
      expect(finalIf.elseBlock!.statements.first, isA<ReturnStatementNode>());
    });
  });

  group('else-if + loop edits (M8.0c)', () {
    test('idempotence on function_body_with_else_if.dart', () {
      final source = _loadFixture('function_body_with_else_if.dart');
      final body = parseFunctionBody(source);
      final result = applySourceEdits(source, const <SourceEdit>[]);
      expect(result, equals(source));
      expect(body.statements, isNotEmpty);
    });

    test('idempotence on function_body_with_loops.dart', () {
      final source = _loadFixture('function_body_with_loops.dart');
      final body = parseFunctionBody(source);
      final result = applySourceEdits(source, const <SourceEdit>[]);
      expect(result, equals(source));
      expect(body.statements, isNotEmpty);
    });

    test('changeIfCondition on an inner else-if branch', () {
      final source = _loadFixture('function_body_with_else_if.dart');
      final body = parseFunctionBody(source);
      final head = body.statements[1] as IfStatementNode;
      // Edit the middle branch's condition.
      final middle = head.elseIf!;
      expect(middle.conditionSource, equals('clamped >= 80'));

      final edit = FunctionBodyEditPlanner.changeIfCondition(
        statement: middle,
        newConditionSource: 'clamped >= 85',
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseFunctionBody(newSource);
      final reHead = reparsed.statements[1] as IfStatementNode;
      expect(reHead.elseIf!.conditionSource, equals('clamped >= 85'));
      // Head and tail branches untouched.
      expect(reHead.conditionSource, equals('clamped >= 90'));
      expect(reHead.elseIf!.elseIf!.conditionSource, equals('clamped >= 70'));
    });

    test('addStatement into a deep else-if branch (recursive)', () {
      final source = _loadFixture('function_body_with_else_if.dart');
      final body = parseFunctionBody(source);
      final head = body.statements[1] as IfStatementNode;
      // Reach the second else-if (C-tier) branch and prepend a log call.
      final second = head.elseIf!;
      final third = second.elseIf!;
      expect(third.thenBlock.statements, hasLength(1));

      final edit = FunctionBodyEditPlanner.addStatement(
        block: third.thenBlock,
        index: 0,
        newStatementSource: "log('grade C');",
        source: source,
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseFunctionBody(newSource);
      final reHead = reparsed.statements[1] as IfStatementNode;
      final reThird = reHead.elseIf!.elseIf!;
      expect(reThird.thenBlock.statements, hasLength(2));
      expect(
          reThird.thenBlock.statements.first, isA<ExpressionStatementNode>());
    });

    test('changeWhileCondition rewrites the while condition', () {
      final source = _loadFixture('function_body_with_loops.dart');
      final body = parseFunctionBody(source);
      final wh = body.statements[3] as WhileStatementNode;
      expect(wh.conditionSource, equals('remaining > 100'));

      final edit = FunctionBodyEditPlanner.changeWhileCondition(
        statement: wh,
        newConditionSource: 'remaining > 50',
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseFunctionBody(newSource);
      final reWh = reparsed.statements[3] as WhileStatementNode;
      expect(reWh.conditionSource, equals('remaining > 50'));
    });

    test('addStatement into for-loop body (recursive)', () {
      final source = _loadFixture('function_body_with_loops.dart');
      final body = parseFunctionBody(source);
      final forStmt = body.statements[1] as ForStatementNode;
      expect(forStmt.body.statements, hasLength(1));

      final edit = FunctionBodyEditPlanner.addStatement(
        block: forStmt.body,
        index: 1,
        newStatementSource: 'log(total);',
        source: source,
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseFunctionBody(newSource);
      final reFor = reparsed.statements[1] as ForStatementNode;
      expect(reFor.body.statements, hasLength(2));
      expect(reFor.body.statements.last, isA<ExpressionStatementNode>());
    });

    test('removeStatement from while-loop body', () {
      // Insert a statement into the while body, then remove it.
      final source = _loadFixture('function_body_with_loops.dart');
      final body = parseFunctionBody(source);
      final wh = body.statements[3] as WhileStatementNode;

      final addEdit = FunctionBodyEditPlanner.addStatement(
        block: wh.body,
        index: 0,
        newStatementSource: 'log(remaining);',
        source: source,
      );
      final intermediate = applySourceEdits(source, [addEdit]);

      final intermediateBody = parseFunctionBody(intermediate);
      final intermediateWh =
          intermediateBody.statements[3] as WhileStatementNode;
      expect(intermediateWh.body.statements, hasLength(2));

      final logStmt = intermediateWh.body.statements.first;
      final removeEdit = FunctionBodyEditPlanner.removeStatement(
        statement: logStmt,
        source: intermediate,
      );
      final finalSource = applySourceEdits(intermediate, [removeEdit]);

      final finalBody = parseFunctionBody(finalSource);
      final finalWh = finalBody.statements[3] as WhileStatementNode;
      expect(finalWh.body.statements, hasLength(1));
      expect(finalWh.body.statements.first, isA<ExpressionStatementNode>());
    });
  });

  group('replaceStatement', () {
    test('replaces an ExpressionStatement with a different call', () {
      final source = _loadFixture('function_body_simple.dart');
      final body = parseFunctionBody(source);
      final saveStmt = body.statements[3];
      expect(saveStmt, isA<ExpressionStatementNode>());

      final edit = FunctionBodyEditPlanner.replaceStatement(
        statement: saveStmt,
        newStatementSource: 'persist(id, normalized);',
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseFunctionBody(newSource);
      final reparsedStmt = reparsed.statements[3] as ExpressionStatementNode;
      expect(reparsedStmt.expressionSource, startsWith('persist('));
    });
  });
}
