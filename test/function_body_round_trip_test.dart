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

  group('do-while + try + throw edits (M8.0d)', () {
    test('idempotence on function_body_with_do_while.dart', () {
      final source = _loadFixture('function_body_with_do_while.dart');
      final body = parseFunctionBody(source);
      expect(applySourceEdits(source, const <SourceEdit>[]), equals(source));
      expect(body.statements, hasLength(3));
    });

    test('idempotence on function_body_with_try.dart', () {
      final source = _loadFixture('function_body_with_try.dart');
      final body = parseFunctionBody(source);
      expect(applySourceEdits(source, const <SourceEdit>[]), equals(source));
      expect(body.statements, hasLength(3));
    });

    test('idempotence on function_body_with_throw.dart', () {
      final source = _loadFixture('function_body_with_throw.dart');
      final body = parseFunctionBody(source);
      expect(applySourceEdits(source, const <SourceEdit>[]), equals(source));
      expect(body.statements, hasLength(2));
    });

    test('changeDoWhileCondition rewrites the trailing condition', () {
      final source = _loadFixture('function_body_with_do_while.dart');
      final body = parseFunctionBody(source);
      final doStmt = body.statements[1] as DoStatementNode;

      final edit = FunctionBodyEditPlanner.changeDoWhileCondition(
        statement: doStmt,
        newConditionSource: 'n >= floor',
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseFunctionBody(newSource);
      final reparsedDo = reparsed.statements[1] as DoStatementNode;
      expect(reparsedDo.conditionSource, equals('n >= floor'));
      // Body unchanged.
      expect(reparsedDo.body.statements, hasLength(1));
    });

    test('addStatement recurses into a do-while body', () {
      final source = _loadFixture('function_body_with_do_while.dart');
      final body = parseFunctionBody(source);
      final doStmt = body.statements[1] as DoStatementNode;

      final edit = FunctionBodyEditPlanner.addStatement(
        block: doStmt.body,
        index: doStmt.body.statements.length,
        newStatementSource: 'log(n);',
        source: source,
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseFunctionBody(newSource);
      final reparsedDo = reparsed.statements[1] as DoStatementNode;
      expect(reparsedDo.body.statements, hasLength(2));
      expect(
        reparsedDo.body.statements.last,
        isA<ExpressionStatementNode>(),
      );
    });

    test('addStatement recurses into a try block', () {
      final source = _loadFixture('function_body_with_try.dart');
      final body = parseFunctionBody(source);
      final tryStmt = body.statements[1] as TryStatementNode;

      final edit = FunctionBodyEditPlanner.addStatement(
        block: tryStmt.tryBlock,
        index: 0,
        newStatementSource: 'log("attempting");',
        source: source,
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseFunctionBody(newSource);
      final reparsedTry = reparsed.statements[1] as TryStatementNode;
      expect(reparsedTry.tryBlock.statements, hasLength(2));
      expect(
        reparsedTry.tryBlock.statements.first,
        isA<ExpressionStatementNode>(),
      );
    });

    test('removeStatement removes a line from a catch clause body', () {
      final source = _loadFixture('function_body_with_try.dart');
      final body = parseFunctionBody(source);
      final tryStmt = body.statements[1] as TryStatementNode;
      final firstCatch = tryStmt.catchClauses[0];
      expect(firstCatch.body.statements, hasLength(2));

      // Drop the trailing `result = fallback;` assignment.
      final lastStmt = firstCatch.body.statements.last;
      final edit = FunctionBodyEditPlanner.removeStatement(
        statement: lastStmt,
        source: source,
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseFunctionBody(newSource);
      final reparsedTry = reparsed.statements[1] as TryStatementNode;
      expect(reparsedTry.catchClauses[0].body.statements, hasLength(1));
    });

    test(
        'changeWhileCondition-style edit on the finally block reuses '
        'addStatement', () {
      final source = _loadFixture('function_body_with_try.dart');
      final body = parseFunctionBody(source);
      final tryStmt = body.statements[1] as TryStatementNode;
      expect(tryStmt.finallyBlock, isNotNull);

      final edit = FunctionBodyEditPlanner.addStatement(
        block: tryStmt.finallyBlock!,
        index: tryStmt.finallyBlock!.statements.length,
        newStatementSource: 'log("really done");',
        source: source,
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseFunctionBody(newSource);
      final reparsedTry = reparsed.statements[1] as TryStatementNode;
      expect(reparsedTry.finallyBlock!.statements, hasLength(2));
    });

    test('changeThrownExpression rewrites the thrown expression', () {
      final source = _loadFixture('function_body_with_throw.dart');
      final body = parseFunctionBody(source);
      final ifStmt = body.statements[0] as IfStatementNode;
      final thrown = ifStmt.thenBlock.statements.first as ThrowStatementNode;

      final edit = FunctionBodyEditPlanner.changeThrownExpression(
        statement: thrown,
        newExpressionSource: "StateError('non-positive: \$n')",
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseFunctionBody(newSource);
      final reparsedIf = reparsed.statements[0] as IfStatementNode;
      final reparsedThrow =
          reparsedIf.thenBlock.statements.first as ThrowStatementNode;
      expect(reparsedThrow.expressionSource, startsWith('StateError'));
    });
  });

  group('switch edits (M8.0e)', () {
    test('idempotence on function_body_with_switch.dart', () {
      final source = _loadFixture('function_body_with_switch.dart');
      final body = parseFunctionBody(source);
      expect(applySourceEdits(source, const <SourceEdit>[]), equals(source));
      expect(body.statements, hasLength(1));
    });

    test('changeSwitchExpression rewrites the switched value', () {
      final source = _loadFixture('function_body_with_switch.dart');
      final body = parseFunctionBody(source);
      final sw = body.statements.first as SwitchStatementNode;

      final edit = FunctionBodyEditPlanner.changeSwitchExpression(
        statement: sw,
        newExpressionSource: 'value.runtimeType',
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseFunctionBody(newSource);
      final reparsedSw = reparsed.statements.first as SwitchStatementNode;
      expect(reparsedSw.expressionSource, equals('value.runtimeType'));
      expect(reparsedSw.members, hasLength(7));
    });

    test('changeSwitchCasePattern rewrites a legacy case pattern', () {
      final source = _loadFixture('function_body_with_switch.dart');
      final body = parseFunctionBody(source);
      final sw = body.statements.first as SwitchStatementNode;
      final c0 = sw.members[0] as SwitchCaseNode;

      final edit = FunctionBodyEditPlanner.changeSwitchCasePattern(
        caseMember: c0,
        newPatternSource: '1',
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseFunctionBody(newSource);
      final reparsedSw = reparsed.statements.first as SwitchStatementNode;
      final reparsedC0 = reparsedSw.members[0] as SwitchCaseNode;
      expect(reparsedC0.patternSource, equals('1'));
    });

    test('changeSwitchCaseGuard rewrites a pattern-case guard', () {
      final source = _loadFixture('function_body_with_switch.dart');
      final body = parseFunctionBody(source);
      final sw = body.statements.first as SwitchStatementNode;
      // members[2] is `case int n when n < 0:` (after `case 0:` and the
      // logical-or alternative).
      final c2 = sw.members[2] as SwitchCaseNode;

      final edit = FunctionBodyEditPlanner.changeSwitchCaseGuard(
        caseMember: c2,
        newGuardSource: 'n <= -1',
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseFunctionBody(newSource);
      final reparsedSw = reparsed.statements.first as SwitchStatementNode;
      final reparsedC2 = reparsedSw.members[2] as SwitchCaseNode;
      expect(reparsedC2.whenGuardSource, equals('n <= -1'));
    });

    test('changeSwitchCaseGuard throws when no guard exists', () {
      final source = _loadFixture('function_body_with_switch.dart');
      final body = parseFunctionBody(source);
      final sw = body.statements.first as SwitchStatementNode;
      // members[0] is `case 0:` — no guard.
      final c0 = sw.members[0] as SwitchCaseNode;
      expect(
        () => FunctionBodyEditPlanner.changeSwitchCaseGuard(
          caseMember: c0,
          newGuardSource: 'true',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('addStatement into a non-empty case body', () {
      final source = _loadFixture('function_body_with_switch.dart');
      final body = parseFunctionBody(source);
      final sw = body.statements.first as SwitchStatementNode;
      final c0 = sw.members[0] as SwitchCaseNode;
      expect(c0.body.statements, hasLength(1));

      final edit = FunctionBodyEditPlanner.addStatement(
        block: c0.body,
        index: 0,
        newStatementSource: 'log("zero");',
        source: source,
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseFunctionBody(newSource);
      final reparsedSw = reparsed.statements.first as SwitchStatementNode;
      final reparsedC0 = reparsedSw.members[0] as SwitchCaseNode;
      expect(reparsedC0.body.statements, hasLength(2));
      expect(
        reparsedC0.body.statements.first,
        isA<ExpressionStatementNode>(),
      );
    });

    test('addStatement into a brace-less EMPTY case body (fall-through)', () {
      const source = '''
String f(int x) {
  switch (x) {
    case 1:
    case 2:
      return 'small';
    default:
      return 'other';
  }
}
''';
      final body = parseFunctionBody(source);
      final sw = body.statements.first as SwitchStatementNode;
      // members[0] is `case 1:` with an empty body (fall-through).
      final c0 = sw.members[0] as SwitchCaseNode;
      expect(c0.body.statements, isEmpty);

      final edit = FunctionBodyEditPlanner.addStatement(
        block: c0.body,
        index: 0,
        newStatementSource: 'log("one");',
        source: source,
      );
      final newSource = applySourceEdits(source, [edit]);

      // Re-parse: case 1 should now have 1 statement, the next case
      // still parses cleanly, no syntax damage.
      final reparsed = parseFunctionBody(newSource);
      final reparsedSw = reparsed.statements.first as SwitchStatementNode;
      final reparsedC0 = reparsedSw.members[0] as SwitchCaseNode;
      expect(reparsedC0.body.statements, hasLength(1));
      expect(reparsedSw.members, hasLength(3));
    });

    test('removeStatement from a case body', () {
      final source = _loadFixture('function_body_with_switch.dart');
      final body = parseFunctionBody(source);
      final sw = body.statements.first as SwitchStatementNode;
      final c0 = sw.members[0] as SwitchCaseNode;

      final edit = FunctionBodyEditPlanner.removeStatement(
        statement: c0.body.statements.first,
        source: source,
      );
      final newSource = applySourceEdits(source, [edit]);

      // The case body is now empty, but the switch still parses.
      final reparsed = parseFunctionBody(newSource);
      final reparsedSw = reparsed.statements.first as SwitchStatementNode;
      final reparsedC0 = reparsedSw.members[0] as SwitchCaseNode;
      expect(reparsedC0.body.statements, isEmpty);
    });
  });

  group('pattern-internal edits (M8.0f)', () {
    test('renameDeclaredPatternVariable renames `n` → `value`', () {
      final source = _loadFixture('function_body_with_switch.dart');
      final body = parseFunctionBody(source);
      final sw = body.statements.first as SwitchStatementNode;
      // members[2] is `case int n when n < 0:`.
      final c2 = sw.members[2] as SwitchCaseNode;
      final p = c2.pattern as DeclaredVariablePatternNode;

      final edit = FunctionBodyEditPlanner.renameDeclaredPatternVariable(
        pattern: p,
        newName: 'value',
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseFunctionBody(newSource);
      final reparsedSw = reparsed.statements.first as SwitchStatementNode;
      final reparsedC2 = reparsedSw.members[2] as SwitchCaseNode;
      final reparsedP = reparsedC2.pattern as DeclaredVariablePatternNode;
      expect(reparsedP.name, equals('value'));
      // Guard still references the old name — that's expected; rename
      // only touches the pattern. (Compile error in the new source,
      // but the kernel's contract is source preservation, not type
      // safety. Future symbol-aware rename op can handle the guard.)
      expect(reparsedC2.whenGuardSource, equals('n < 0'));
    });

    test('changeDeclaredPatternType swaps `int` → `num`', () {
      final source = _loadFixture('function_body_with_switch.dart');
      final body = parseFunctionBody(source);
      final sw = body.statements.first as SwitchStatementNode;
      final c2 = sw.members[2] as SwitchCaseNode;
      final p = c2.pattern as DeclaredVariablePatternNode;

      final edit = FunctionBodyEditPlanner.changeDeclaredPatternType(
        pattern: p,
        newType: 'num',
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseFunctionBody(newSource);
      final reparsedSw = reparsed.statements.first as SwitchStatementNode;
      final reparsedC2 = reparsedSw.members[2] as SwitchCaseNode;
      final reparsedP = reparsedC2.pattern as DeclaredVariablePatternNode;
      expect(reparsedP.typeSource, equals('num'));
      expect(reparsedP.name, equals('n'));
    });

    test('changeDeclaredPatternType throws on `var x` patterns', () {
      const source = '''
String f(Object o) {
  switch (o) {
    case var x:
      return 'x=\$x';
  }
}
''';
      final body = parseFunctionBody(source);
      final sw = body.statements.first as SwitchStatementNode;
      final c0 = sw.members[0] as SwitchCaseNode;
      final p = c0.pattern as DeclaredVariablePatternNode;

      expect(
        () => FunctionBodyEditPlanner.changeDeclaredPatternType(
          pattern: p,
          newType: 'int',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('changeConstantPatternExpression swaps `0` → `42`', () {
      final source = _loadFixture('function_body_with_switch.dart');
      final body = parseFunctionBody(source);
      final sw = body.statements.first as SwitchStatementNode;
      final c0 = sw.members[0] as SwitchCaseNode;
      final p = c0.pattern as ConstantPatternNode;

      final edit = FunctionBodyEditPlanner.changeConstantPatternExpression(
        pattern: p,
        newExpressionSource: '42',
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseFunctionBody(newSource);
      final reparsedSw = reparsed.statements.first as SwitchStatementNode;
      final reparsedC0 = reparsedSw.members[0] as SwitchCaseNode;
      final reparsedP = reparsedC0.pattern as ConstantPatternNode;
      expect(reparsedP.expressionSource, equals('42'));
    });

    test('changeConstantPatternExpression on a logical-or operand', () {
      final source = _loadFixture('function_body_with_switch.dart');
      final body = parseFunctionBody(source);
      final sw = body.statements.first as SwitchStatementNode;
      // members[1] is `case 1 || 2 || 3:`.
      final c1 = sw.members[1] as SwitchCaseNode;
      final or = c1.pattern as LogicalOrPatternNode;
      // Rewrite the middle operand: `2` → `20`.
      final mid = or.operands[1] as ConstantPatternNode;

      final edit = FunctionBodyEditPlanner.changeConstantPatternExpression(
        pattern: mid,
        newExpressionSource: '20',
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseFunctionBody(newSource);
      final reparsedSw = reparsed.statements.first as SwitchStatementNode;
      final reparsedC1 = reparsedSw.members[1] as SwitchCaseNode;
      expect(reparsedC1.patternSource, equals('1 || 20 || 3'));
      final reparsedOr = reparsedC1.pattern as LogicalOrPatternNode;
      expect(reparsedOr.operands, hasLength(3));
      expect(
        (reparsedOr.operands[1] as ConstantPatternNode).expressionSource,
        equals('20'),
      );
    });
  });

  group('object/record pattern edits (M8.0g)', () {
    test('idempotence on function_body_with_object_record_patterns.dart', () {
      final source =
          _loadFixture('function_body_with_object_record_patterns.dart');
      final body = parseFunctionBody(source);
      expect(applySourceEdits(source, const <SourceEdit>[]), equals(source));
      expect(body.statements, hasLength(1));
    });

    test('changeObjectPatternType swaps Point → Coord', () {
      final source =
          _loadFixture('function_body_with_object_record_patterns.dart');
      final body = parseFunctionBody(source);
      final sw = body.statements.first as SwitchStatementNode;
      // members[0] is `case Point(x: 0, y: 0):`.
      final c0 = sw.members[0] as SwitchCaseNode;
      final op = c0.pattern as ObjectPatternNode;

      final edit = FunctionBodyEditPlanner.changeObjectPatternType(
        pattern: op,
        newTypeNameSource: 'Coord',
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseFunctionBody(newSource);
      final reparsedSw = reparsed.statements.first as SwitchStatementNode;
      final reparsedC0 = reparsedSw.members[0] as SwitchCaseNode;
      final reparsedOp = reparsedC0.pattern as ObjectPatternNode;
      expect(reparsedOp.typeNameSource, equals('Coord'));
      // Fields preserved.
      expect(reparsedOp.fields, hasLength(2));
      expect(reparsedOp.fields[0].fieldName, equals('x'));
    });

    test('renamePatternFieldName renames x → left', () {
      final source =
          _loadFixture('function_body_with_object_record_patterns.dart');
      final body = parseFunctionBody(source);
      final sw = body.statements.first as SwitchStatementNode;
      final c0 = sw.members[0] as SwitchCaseNode;
      final op = c0.pattern as ObjectPatternNode;

      final edit = FunctionBodyEditPlanner.renamePatternFieldName(
        field: op.fields[0],
        newName: 'left',
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseFunctionBody(newSource);
      final reparsedOp = (reparsed.statements.first as SwitchStatementNode)
          .members[0] as SwitchCaseNode;
      final reparsedField = (reparsedOp.pattern as ObjectPatternNode).fields[0];
      expect(reparsedField.fieldName, equals('left'));
    });

    test('renamePatternFieldName throws on positional fields', () {
      final source =
          _loadFixture('function_body_with_object_record_patterns.dart');
      final body = parseFunctionBody(source);
      final sw = body.statements.first as SwitchStatementNode;
      // members[3] is `case (int a, int b):` — positional record.
      final c3 = sw.members[3] as SwitchCaseNode;
      final rp = c3.pattern as RecordPatternNode;
      expect(rp.fields[0].isPositional, isTrue);

      expect(
        () => FunctionBodyEditPlanner.renamePatternFieldName(
          field: rp.fields[0],
          newName: 'first',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('renamePatternFieldName throws on shorthand fields', () {
      final source =
          _loadFixture('function_body_with_object_record_patterns.dart');
      final body = parseFunctionBody(source);
      final sw = body.statements.first as SwitchStatementNode;
      // members[2] is `case Rect(:var width, :var height):` — shorthand.
      final c2 = sw.members[2] as SwitchCaseNode;
      final op = c2.pattern as ObjectPatternNode;
      expect(op.fields[0].isShorthand, isTrue);

      expect(
        () => FunctionBodyEditPlanner.renamePatternFieldName(
          field: op.fields[0],
          newName: 'w',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('replacePatternFieldPattern swaps a constant for a typed var', () {
      final source =
          _loadFixture('function_body_with_object_record_patterns.dart');
      final body = parseFunctionBody(source);
      final sw = body.statements.first as SwitchStatementNode;
      final c0 = sw.members[0] as SwitchCaseNode;
      final op = c0.pattern as ObjectPatternNode;

      // Field 0: `x: 0` → `x: int n`.
      final edit = FunctionBodyEditPlanner.replacePatternFieldPattern(
        field: op.fields[0],
        newPatternSource: 'int n',
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseFunctionBody(newSource);
      final reparsedOp = ((reparsed.statements.first as SwitchStatementNode)
              .members[0] as SwitchCaseNode)
          .pattern as ObjectPatternNode;
      final reparsedField = reparsedOp.fields[0];
      expect(reparsedField.fieldName, equals('x'));
      final inner = reparsedField.pattern as DeclaredVariablePatternNode;
      expect(inner.typeSource, equals('int'));
      expect(inner.name, equals('n'));
    });

    test('existing pattern-internal ops work recursively inside fields', () {
      // Rename `x` → `xValue` inside `case Point(x: var x, ...) when x == y:`.
      final source =
          _loadFixture('function_body_with_object_record_patterns.dart');
      final body = parseFunctionBody(source);
      final sw = body.statements.first as SwitchStatementNode;
      // members[1] is the Point(x: var x, y: var y) with guard.
      final c1 = sw.members[1] as SwitchCaseNode;
      final op = c1.pattern as ObjectPatternNode;
      final xField = op.fields[0];
      final inner = xField.pattern as DeclaredVariablePatternNode;

      final edit = FunctionBodyEditPlanner.renameDeclaredPatternVariable(
        pattern: inner,
        newName: 'xValue',
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseFunctionBody(newSource);
      final reparsedOp = ((reparsed.statements.first as SwitchStatementNode)
              .members[1] as SwitchCaseNode)
          .pattern as ObjectPatternNode;
      final reparsedInner =
          reparsedOp.fields[0].pattern as DeclaredVariablePatternNode;
      expect(reparsedInner.name, equals('xValue'));
    });

    test('changeConstantPatternExpression deep inside a record field', () {
      // case Point(x: 0, y: 0): → case Point(x: 0, y: 7):
      final source =
          _loadFixture('function_body_with_object_record_patterns.dart');
      final body = parseFunctionBody(source);
      final sw = body.statements.first as SwitchStatementNode;
      final c0 = sw.members[0] as SwitchCaseNode;
      final op = c0.pattern as ObjectPatternNode;
      final yConstant = op.fields[1].pattern as ConstantPatternNode;

      final edit = FunctionBodyEditPlanner.changeConstantPatternExpression(
        pattern: yConstant,
        newExpressionSource: '7',
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseFunctionBody(newSource);
      final reparsedOp = ((reparsed.statements.first as SwitchStatementNode)
              .members[0] as SwitchCaseNode)
          .pattern as ObjectPatternNode;
      expect(
        (reparsedOp.fields[1].pattern as ConstantPatternNode).expressionSource,
        equals('7'),
      );
    });
  });

  group('remaining pattern edits (M8.0h)', () {
    test('idempotence on function_body_with_remaining_patterns.dart', () {
      final source = _loadFixture('function_body_with_remaining_patterns.dart');
      final body = parseFunctionBody(source);
      expect(applySourceEdits(source, const <SourceEdit>[]), equals(source));
      expect(body.statements, hasLength(1));
    });

    test('changeRelationalPatternOperator > -> >=', () {
      final source = _loadFixture('function_body_with_remaining_patterns.dart');
      final body = parseFunctionBody(source);
      final sw = body.statements.first as SwitchStatementNode;
      final c4 = sw.members[4] as SwitchCaseNode;
      final rp = c4.pattern as RelationalPatternNode;

      final edit = FunctionBodyEditPlanner.changeRelationalPatternOperator(
        pattern: rp,
        newOperator: '>=',
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseFunctionBody(newSource);
      final reparsedRp = ((reparsed.statements.first as SwitchStatementNode)
              .members[4] as SwitchCaseNode)
          .pattern as RelationalPatternNode;
      expect(reparsedRp.operator, equals('>='));
      expect(reparsedRp.operandSource, equals('100'));
    });

    test('changeRelationalPatternOperand 100 -> 200', () {
      final source = _loadFixture('function_body_with_remaining_patterns.dart');
      final body = parseFunctionBody(source);
      final sw = body.statements.first as SwitchStatementNode;
      final c4 = sw.members[4] as SwitchCaseNode;
      final rp = c4.pattern as RelationalPatternNode;

      final edit = FunctionBodyEditPlanner.changeRelationalPatternOperand(
        pattern: rp,
        newOperandSource: '200',
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseFunctionBody(newSource);
      final reparsedRp = ((reparsed.statements.first as SwitchStatementNode)
              .members[4] as SwitchCaseNode)
          .pattern as RelationalPatternNode;
      expect(reparsedRp.operator, equals('>'));
      expect(reparsedRp.operandSource, equals('200'));
    });

    test('changeCastPatternType int -> num', () {
      final source = _loadFixture('function_body_with_remaining_patterns.dart');
      final body = parseFunctionBody(source);
      final sw = body.statements.first as SwitchStatementNode;
      final c8 = sw.members[8] as SwitchCaseNode;
      final cast = c8.pattern as CastPatternNode;

      final edit = FunctionBodyEditPlanner.changeCastPatternType(
        pattern: cast,
        newTypeSource: 'num',
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseFunctionBody(newSource);
      final reparsedCast = ((reparsed.statements.first as SwitchStatementNode)
              .members[8] as SwitchCaseNode)
          .pattern as CastPatternNode;
      expect(reparsedCast.typeSource, equals('num'));
    });

    test("changeMapPatternEntryKey 'name' -> 'username'", () {
      final source = _loadFixture('function_body_with_remaining_patterns.dart');
      final body = parseFunctionBody(source);
      final sw = body.statements.first as SwitchStatementNode;
      final c3 = sw.members[3] as SwitchCaseNode;
      final mp = c3.pattern as MapPatternNode;
      final entry = mp.elements[0] as MapPatternEntryNode;

      final edit = FunctionBodyEditPlanner.changeMapPatternEntryKey(
        entry: entry,
        newKeyExpressionSource: "'username'",
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseFunctionBody(newSource);
      final reparsedMp = ((reparsed.statements.first as SwitchStatementNode)
              .members[3] as SwitchCaseNode)
          .pattern as MapPatternNode;
      final reparsedEntry = reparsedMp.elements[0] as MapPatternEntryNode;
      expect(reparsedEntry.keyExpressionSource, equals("'username'"));
    });

    test('renameDeclaredPatternVariable inside null-check propagates', () {
      final source = _loadFixture('function_body_with_remaining_patterns.dart');
      final body = parseFunctionBody(source);
      final sw = body.statements.first as SwitchStatementNode;
      final c6 = sw.members[6] as SwitchCaseNode;
      final nc = c6.pattern as NullCheckPatternNode;
      final inner = nc.innerPattern as DeclaredVariablePatternNode;

      final edit = FunctionBodyEditPlanner.renameDeclaredPatternVariable(
        pattern: inner,
        newName: 'value',
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseFunctionBody(newSource);
      final reparsedNc = ((reparsed.statements.first as SwitchStatementNode)
              .members[6] as SwitchCaseNode)
          .pattern as NullCheckPatternNode;
      final reparsedInner =
          reparsedNc.innerPattern as DeclaredVariablePatternNode;
      expect(reparsedInner.name, equals('value'));
    });

    test('changeRelationalPatternOperand deep inside a logical-and', () {
      final source = _loadFixture('function_body_with_remaining_patterns.dart');
      final body = parseFunctionBody(source);
      final sw = body.statements.first as SwitchStatementNode;
      final c10 = sw.members[10] as SwitchCaseNode;
      final and = c10.pattern as LogicalAndPatternNode;
      final rel = and.operands[1] as RelationalPatternNode;

      final edit = FunctionBodyEditPlanner.changeRelationalPatternOperand(
        pattern: rel,
        newOperandSource: '10',
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseFunctionBody(newSource);
      final reparsedAnd = ((reparsed.statements.first as SwitchStatementNode)
              .members[10] as SwitchCaseNode)
          .pattern as LogicalAndPatternNode;
      final reparsedRel = reparsedAnd.operands[1] as RelationalPatternNode;
      expect(reparsedRel.operandSource, equals('10'));
    });
  });

  group('switch expression edits (M8.0h)', () {
    test('idempotence on function_body_with_switch_expressions.dart', () {
      final source = _loadFixture('function_body_with_switch_expressions.dart');
      expect(applySourceEdits(source, const <SourceEdit>[]), equals(source));
      final body = parseFunctionBody(source);
      final v = body.statements[0] as VariableDeclarationStatementNode;
      expect(v.variables.first.initializerSwitchExpression, isNotNull);
    });

    test('switch expression case patterns are recursively editable', () {
      final source = _loadFixture('function_body_with_switch_expressions.dart');
      final body = parseFunctionBody(source);
      final v = body.statements[0] as VariableDeclarationStatementNode;
      final sx = v.variables.first.initializerSwitchExpression!;
      final patternN = sx.cases[2].pattern as DeclaredVariablePatternNode;

      final edit = FunctionBodyEditPlanner.renameDeclaredPatternVariable(
        pattern: patternN,
        newName: 'value',
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseFunctionBody(newSource);
      final reparsedV =
          reparsed.statements[0] as VariableDeclarationStatementNode;
      final reparsedSx = reparsedV.variables.first.initializerSwitchExpression!;
      final reparsedPattern =
          reparsedSx.cases[2].pattern as DeclaredVariablePatternNode;
      expect(reparsedPattern.name, equals('value'));
    });
  });

  group('for-loop header edits (M8.2)', () {
    test('idempotence on function_body_with_for_headers.dart', () {
      final source = _loadFixture('function_body_with_for_headers.dart');
      expect(applySourceEdits(source, const <SourceEdit>[]), equals(source));
    });

    test('changeCStyleForCondition rewrites the c-style condition', () {
      final source = _loadFixture('function_body_with_for_headers.dart');
      final body = parseFunctionBody(source);
      final f = body.statements[1] as ForStatementNode;

      final edit = FunctionBodyEditPlanner.changeCStyleForCondition(
        header: f.header,
        newConditionSource: 'i < 100',
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseFunctionBody(newSource);
      final reparsedF = reparsed.statements[1] as ForStatementNode;
      final h = reparsedF.header as CStyleForHeader;
      expect(h.conditionSource, equals('i < 100'));
    });

    test('replaceCStyleForUpdater rewrites the updater', () {
      final source = _loadFixture('function_body_with_for_headers.dart');
      final body = parseFunctionBody(source);
      final f = body.statements[1] as ForStatementNode;

      final edit = FunctionBodyEditPlanner.replaceCStyleForUpdater(
        header: f.header,
        updaterIndex: 0,
        newUpdaterSource: 'i += 2',
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseFunctionBody(newSource);
      final reparsedF = reparsed.statements[1] as ForStatementNode;
      final h = reparsedF.header as CStyleForHeader;
      expect(h.updaterSources, equals(['i += 2']));
    });

    test('renameForEachLoopVariable renames the loop variable', () {
      final source = _loadFixture('function_body_with_for_headers.dart');
      final body = parseFunctionBody(source);
      // body.statements[2] is `for (final user in xs) {...}`.
      final f = body.statements[2] as ForStatementNode;

      final edit = FunctionBodyEditPlanner.renameForEachLoopVariable(
        header: f.header,
        newName: 'item',
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseFunctionBody(newSource);
      final reparsedF = reparsed.statements[2] as ForStatementNode;
      final h = reparsedF.header as ForEachHeader;
      expect(h.loopVariableName, equals('item'));
    });

    test('changeForEachLoopVariableType swaps int → num', () {
      final source = _loadFixture('function_body_with_for_headers.dart');
      final body = parseFunctionBody(source);
      // body.statements[3] is `for (int x in xs) {...}`.
      final f = body.statements[3] as ForStatementNode;

      final edit = FunctionBodyEditPlanner.changeForEachLoopVariableType(
        header: f.header,
        newType: 'num',
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseFunctionBody(newSource);
      final reparsedF = reparsed.statements[3] as ForStatementNode;
      final h = reparsedF.header as ForEachHeader;
      expect(h.typeSource, equals('num'));
    });

    test('changeForEachIterable rewrites the iterable expression', () {
      final source = _loadFixture('function_body_with_for_headers.dart');
      final body = parseFunctionBody(source);
      final f = body.statements[2] as ForStatementNode;

      final edit = FunctionBodyEditPlanner.changeForEachIterable(
        header: f.header,
        newIterableSource: 'activeUsers',
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseFunctionBody(newSource);
      final reparsedF = reparsed.statements[2] as ForStatementNode;
      final h = reparsedF.header as ForEachHeader;
      expect(h.iterableSource, equals('activeUsers'));
    });

    test('changeForEachLoopVariableType throws when no type', () {
      final source = _loadFixture('function_body_with_for_headers.dart');
      final body = parseFunctionBody(source);
      // body.statements[2] is `for (final user in xs)` — no type.
      final f = body.statements[2] as ForStatementNode;
      expect(
        () => FunctionBodyEditPlanner.changeForEachLoopVariableType(
          header: f.header,
          newType: 'String',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('changeCStyleForCondition throws on a for-each header', () {
      final source = _loadFixture('function_body_with_for_headers.dart');
      final body = parseFunctionBody(source);
      final f = body.statements[2] as ForStatementNode;
      expect(
        () => FunctionBodyEditPlanner.changeCStyleForCondition(
          header: f.header,
          newConditionSource: 'true',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('expression-internal edits (M8.2)', () {
    test('idempotence on function_body_with_expressions.dart', () {
      final source = _loadFixture('function_body_with_expressions.dart');
      expect(applySourceEdits(source, const <SourceEdit>[]), equals(source));
    });

    test('changeMethodInvocationName: print → log', () {
      final source = _loadFixture('function_body_with_expressions.dart');
      final body = parseFunctionBody(source);
      final stmt = body.statements[0] as ExpressionStatementNode;
      final m = stmt.expression as MethodInvocationExpressionNode;

      final edit = FunctionBodyEditPlanner.changeMethodInvocationName(
        expression: m,
        newMethodName: 'log',
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseFunctionBody(newSource);
      final reparsedStmt = reparsed.statements[0] as ExpressionStatementNode;
      final reparsedM =
          reparsedStmt.expression as MethodInvocationExpressionNode;
      expect(reparsedM.methodName, equals('log'));
    });

    test('changeMethodInvocationArguments: (x) → (x, y)', () {
      final source = _loadFixture('function_body_with_expressions.dart');
      final body = parseFunctionBody(source);
      final stmt = body.statements[0] as ExpressionStatementNode;
      final m = stmt.expression as MethodInvocationExpressionNode;

      final edit = FunctionBodyEditPlanner.changeMethodInvocationArguments(
        expression: m,
        newArgumentsSource: '(x, 42)',
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseFunctionBody(newSource);
      final reparsedStmt = reparsed.statements[0] as ExpressionStatementNode;
      final reparsedM =
          reparsedStmt.expression as MethodInvocationExpressionNode;
      expect(reparsedM.argumentsSource, equals('(x, 42)'));
    });

    test('renameIdentifierExpressionNode: bare `x;` → bare `value;`', () {
      final source = _loadFixture('function_body_with_expressions.dart');
      final body = parseFunctionBody(source);
      final stmt = body.statements[4] as ExpressionStatementNode;
      final id = stmt.expression as IdentifierExpressionNode;

      final edit = FunctionBodyEditPlanner.renameIdentifierExpression(
        expression: id,
        newName: 'value',
      );
      final newSource = applySourceEdits(source, [edit]);

      // Re-parse: the bare-identifier statement now says `value;`.
      final reparsed = parseFunctionBody(newSource);
      final reparsedStmt = reparsed.statements[4] as ExpressionStatementNode;
      expect(
        (reparsedStmt.expression as IdentifierExpressionNode).name,
        equals('value'),
      );
    });

    test('changeBinaryOperator: x + 1 → x - 1', () {
      final source = _loadFixture('function_body_with_expressions.dart');
      final body = parseFunctionBody(source);
      final stmt = body.statements[9] as ExpressionStatementNode;
      final b = stmt.expression as BinaryExpressionNode;

      final edit = FunctionBodyEditPlanner.changeBinaryOperator(
        expression: b,
        newOperator: '-',
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseFunctionBody(newSource);
      final reparsedStmt = reparsed.statements[9] as ExpressionStatementNode;
      final reparsedB = reparsedStmt.expression as BinaryExpressionNode;
      expect(reparsedB.operator, equals('-'));
    });

    test('changeBinaryOperator on nested binary edits the inner only', () {
      const source = '''
void f(int x) {
  x + 1 + 2;
}
''';
      final body = parseFunctionBody(source);
      final stmt = body.statements[0] as ExpressionStatementNode;
      // Outer is `(x + 1) + 2`; left operand is the inner `x + 1`.
      final outer = stmt.expression as BinaryExpressionNode;
      final inner = outer.leftOperand as BinaryExpressionNode;

      final edit = FunctionBodyEditPlanner.changeBinaryOperator(
        expression: inner,
        newOperator: '*',
      );
      final newSource = applySourceEdits(source, [edit]);

      // After edit: `x * 1 + 2;`
      final reparsed = parseFunctionBody(newSource);
      final reparsedStmt = reparsed.statements[0] as ExpressionStatementNode;
      final reparsedOuter = reparsedStmt.expression as BinaryExpressionNode;
      expect(reparsedOuter.operator, equals('+'));
      final reparsedInner = reparsedOuter.leftOperand as BinaryExpressionNode;
      expect(reparsedInner.operator, equals('*'));
    });
  });

  group('M8.3 — new expression kind edits + structured positions', () {
    test('idempotence on function_body_with_more_expressions.dart', () {
      final source = _loadFixture('function_body_with_more_expressions.dart');
      expect(applySourceEdits(source, const <SourceEdit>[]), equals(source));
    });

    test('changeAssignmentOperator: += → -=', () {
      final source = _loadFixture('function_body_with_more_expressions.dart');
      final body = parseFunctionBody(source);
      final ifStmt = body.statements[1] as IfStatementNode;
      final inner = ifStmt.thenBlock.statements[0] as ExpressionStatementNode;
      final asn = inner.expression as AssignmentExpressionNode;

      final edit = FunctionBodyEditPlanner.changeAssignmentOperator(
        expression: asn,
        newOperator: '-=',
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseFunctionBody(newSource);
      final reparsedAsn = ((reparsed.statements[1] as IfStatementNode)
              .thenBlock
              .statements[0] as ExpressionStatementNode)
          .expression as AssignmentExpressionNode;
      expect(reparsedAsn.operator, equals('-='));
    });

    test('changePrefixOperator: - → ~', () {
      final source = _loadFixture('function_body_with_more_expressions.dart');
      final body = parseFunctionBody(source);
      final v = body.statements[6] as VariableDeclarationStatementNode;
      final pre =
          v.variables.first.initializerExpression! as PrefixExpressionNode;

      final edit = FunctionBodyEditPlanner.changePrefixOperator(
        expression: pre,
        newOperator: '~',
      );
      final newSource = applySourceEdits(source, [edit]);

      final reparsed = parseFunctionBody(newSource);
      final reparsedV =
          reparsed.statements[6] as VariableDeclarationStatementNode;
      final reparsedPre = reparsedV.variables.first.initializerExpression!
          as PrefixExpressionNode;
      expect(reparsedPre.operator, equals('~'));
    });

    test('renamePropertyAccess rewrites the property name', () {
      // Analyzer represents `x.y` where x is a SimpleIdentifier as
      // PrefixedIdentifier, not PropertyAccess. To get a real
      // PropertyAccess we need a non-identifier target.
      const source = '''
void f() {
  build().foo;
  print(0);
}
Box build() => Box();
class Box {
  int foo = 0;
}
void print(Object o) {}
''';
      final body = parseFunctionBody(source);
      final stmt = body.statements[0] as ExpressionStatementNode;
      final pa = stmt.expression as PropertyAccessExpressionNode;

      final edit = FunctionBodyEditPlanner.renamePropertyAccess(
        expression: pa,
        newPropertyName: 'bar',
      );
      final newSource = applySourceEdits(source, [edit]);

      expect(newSource, contains('build().bar;'));
    });

    test('changeBinaryOperator works on a structured if-condition', () {
      // The if-statement's condition is now structurally accessible
      // via IfStatementNode.condition. We can edit it directly.
      final source = _loadFixture('function_body_with_more_expressions.dart');
      final body = parseFunctionBody(source);
      final ifStmt = body.statements[1] as IfStatementNode;
      final cond = ifStmt.condition as BinaryExpressionNode;
      expect(cond.operator, equals('>'));

      final edit = FunctionBodyEditPlanner.changeBinaryOperator(
        expression: cond,
        newOperator: '>=',
      );
      final newSource = applySourceEdits(source, [edit]);
      final reparsed = parseFunctionBody(newSource);
      final reparsedIf = reparsed.statements[1] as IfStatementNode;
      final reparsedCond = reparsedIf.condition as BinaryExpressionNode;
      expect(reparsedCond.operator, equals('>='));
    });

    test('renameIdentifierExpression works on a return expression', () {
      const source = '''
int f(int x) {
  return x;
}
''';
      final body = parseFunctionBody(source);
      final ret = body.statements[0] as ReturnStatementNode;
      final id = ret.returnedExpression! as IdentifierExpressionNode;

      final edit = FunctionBodyEditPlanner.renameIdentifierExpression(
        expression: id,
        newName: 'value',
      );
      final newSource = applySourceEdits(source, [edit]);
      expect(newSource, contains('return value;'));
    });

    test('conditional thenExpression accessible via structured init', () {
      // `final tag = n > 0 ? 'pos' : 'neg';`
      final source = _loadFixture('function_body_with_more_expressions.dart');
      final body = parseFunctionBody(source);
      final v = body.statements[4] as VariableDeclarationStatementNode;
      final cond =
          v.variables.first.initializerExpression! as ConditionalExpressionNode;
      final then = cond.thenExpression as LiteralExpressionNode;
      expect(then.source, equals("'pos'"));
    });

    test('await expression: inner method-invocation is structurally edited',
        () {
      // `final result = await fetch();` — rename `fetch` to `pull`.
      final source = _loadFixture('function_body_with_more_expressions.dart');
      final body = parseFunctionBody(source);
      final v = body.statements[5] as VariableDeclarationStatementNode;
      final aw =
          v.variables.first.initializerExpression! as AwaitExpressionNode;
      final m = aw.expression as MethodInvocationExpressionNode;

      final edit = FunctionBodyEditPlanner.changeMethodInvocationName(
        expression: m,
        newMethodName: 'pull',
      );
      final newSource = applySourceEdits(source, [edit]);
      expect(newSource, contains('await pull();'));
    });
  });

  group('M8.4 — 5 more expression kinds', () {
    test('idempotence on function_body_with_more_expression_kinds.dart', () {
      final source =
          _loadFixture('function_body_with_more_expression_kinds.dart');
      expect(applySourceEdits(source, const <SourceEdit>[]), equals(source));
    });

    test('renamePrefixedIdentifierName: Math.pi -> Math.e', () {
      final source =
          _loadFixture('function_body_with_more_expression_kinds.dart');
      final body = parseFunctionBody(source);
      final v = body.statements[2] as VariableDeclarationStatementNode;
      final pi = v.variables.first.initializerExpression!
          as PrefixedIdentifierExpressionNode;

      final edit = FunctionBodyEditPlanner.renamePrefixedIdentifierName(
        expression: pi,
        newName: 'e',
      );
      final newSource = applySourceEdits(source, [edit]);
      expect(newSource, contains('Math.e'));
    });

    test('renamePrefixedIdentifierPrefix: Math.pi -> Calc.pi', () {
      final source =
          _loadFixture('function_body_with_more_expression_kinds.dart');
      final body = parseFunctionBody(source);
      final v = body.statements[2] as VariableDeclarationStatementNode;
      final pi = v.variables.first.initializerExpression!
          as PrefixedIdentifierExpressionNode;

      final edit = FunctionBodyEditPlanner.renamePrefixedIdentifierPrefix(
        expression: pi,
        newPrefix: 'Calc',
      );
      final newSource = applySourceEdits(source, [edit]);
      expect(newSource, contains('Calc.pi'));
    });

    test('changeAsExpressionType: int -> num', () {
      final source =
          _loadFixture('function_body_with_more_expression_kinds.dart');
      final body = parseFunctionBody(source);
      final v = body.statements[3] as VariableDeclarationStatementNode;
      final cast = v.variables.first.initializerExpression! as AsExpressionNode;

      final edit = FunctionBodyEditPlanner.changeAsExpressionType(
        expression: cast,
        newTypeSource: 'num',
      );
      final newSource = applySourceEdits(source, [edit]);
      expect(newSource, contains('value as num'));
    });

    test('changeIsExpressionType: num -> int', () {
      final source =
          _loadFixture('function_body_with_more_expression_kinds.dart');
      final body = parseFunctionBody(source);
      final v = body.statements[4] as VariableDeclarationStatementNode;
      final isE = v.variables.first.initializerExpression! as IsExpressionNode;

      final edit = FunctionBodyEditPlanner.changeIsExpressionType(
        expression: isE,
        newTypeSource: 'int',
      );
      final newSource = applySourceEdits(source, [edit]);
      expect(newSource, contains('value is int'));
    });

    test('changeInstanceCreationConstructorName', () {
      final source =
          _loadFixture('function_body_with_more_expression_kinds.dart');
      final body = parseFunctionBody(source);
      final v = body.statements[1] as VariableDeclarationStatementNode;
      final ic = v.variables.first.initializerExpression!
          as InstanceCreationExpressionNode;

      final edit =
          FunctionBodyEditPlanner.changeInstanceCreationConstructorName(
        expression: ic,
        newConstructorNameSource: 'List<num>.generate',
      );
      final newSource = applySourceEdits(source, [edit]);
      expect(newSource, contains('List<num>.generate(3, 0)'));
    });

    test(
        'changeInstanceCreationArguments: List<int>.filled(3, 0) -> '
        '(5, 1)', () {
      final source =
          _loadFixture('function_body_with_more_expression_kinds.dart');
      final body = parseFunctionBody(source);
      // statements[1] is the List<int>.filled(3, 0) — definitively
      // an InstanceCreationExpression because of `T<args>.named` shape.
      // Bare `Box(1, 2)` would parse as MethodInvocation under
      // unresolved parseString (no type info).
      final v = body.statements[1] as VariableDeclarationStatementNode;
      final ic = v.variables.first.initializerExpression!
          as InstanceCreationExpressionNode;

      final edit = FunctionBodyEditPlanner.changeInstanceCreationArguments(
        expression: ic,
        newArgumentsSource: '(5, 1)',
      );
      final newSource = applySourceEdits(source, [edit]);
      expect(newSource, contains('List<int>.filled(5, 1)'));
    });

    test('bare Box(1, 2) parses as MethodInvocation (no resolution)', () {
      // Document analyzer behavior: parseString doesn't resolve types,
      // so `Box(1, 2)` is indistinguishable from a function call and
      // parses as MethodInvocationExpressionNode. Use `const Foo()`
      // or `Foo<T>.named()` shapes to definitively get instance
      // creation under unresolved parsing.
      final source =
          _loadFixture('function_body_with_more_expression_kinds.dart');
      final body = parseFunctionBody(source);
      final v = body.statements[6] as VariableDeclarationStatementNode;
      final init = v.variables.first.initializerExpression!;
      expect(init, isA<MethodInvocationExpressionNode>());
    });
  });

  group('yield/break/continue/labeled edits (M8.1)', () {
    test('idempotence on function_body_with_yield_break_continue.dart', () {
      final source =
          _loadFixture('function_body_with_yield_break_continue.dart');
      final body = parseFunctionBody(source);
      expect(applySourceEdits(source, const <SourceEdit>[]), equals(source));
      expect(body.statements, hasLength(1));
    });

    test('changeYieldExpression rewrites the yielded value', () {
      final source =
          _loadFixture('function_body_with_yield_break_continue.dart');
      final body = parseFunctionBody(source);
      final labeled = body.statements[0] as LabeledStatementNode;
      final forStmt = labeled.statement as ForStatementNode;
      final y0 = forStmt.body.statements[3] as YieldStatementNode;

      final edit = FunctionBodyEditPlanner.changeYieldExpression(
        statement: y0,
        newExpressionSource: 'v + 1',
      );
      final newSource = applySourceEdits(source, [edit]);
      final reparsed = parseFunctionBody(newSource);
      final reparsedY0 = ((reparsed.statements[0] as LabeledStatementNode)
              .statement as ForStatementNode)
          .body
          .statements[3] as YieldStatementNode;
      expect(reparsedY0.expressionSource, equals('v + 1'));
      expect(reparsedY0.isDelegating, isFalse);
    });

    test('changeBreakLabel rewrites the target label', () {
      final source =
          _loadFixture('function_body_with_yield_break_continue.dart');
      final body = parseFunctionBody(source);
      final labeled = body.statements[0] as LabeledStatementNode;
      final forStmt = labeled.statement as ForStatementNode;
      final secondIf = forStmt.body.statements[2] as IfStatementNode;
      final brk = secondIf.thenBlock.statements.first as BreakStatementNode;

      final edit = FunctionBodyEditPlanner.changeBreakLabel(
        statement: brk,
        newLabel: 'mainLoop',
      );
      final newSource = applySourceEdits(source, [edit]);
      // Note: the labeled statement still says `outer:` — the user
      // would need to update that too (or use a future symbol-aware
      // label rename). Just verify the break's label was rewritten.
      expect(newSource, contains('break mainLoop;'));
    });

    test('changeBreakLabel throws on bare break', () {
      const source = '''
void f() {
  while (true) {
    break;
  }
}
''';
      final body = parseFunctionBody(source);
      final forStmt = body.statements[0] as WhileStatementNode;
      final brk = forStmt.body.statements.first as BreakStatementNode;
      expect(
        () => FunctionBodyEditPlanner.changeBreakLabel(
          statement: brk,
          newLabel: 'foo',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('renameStatementLabel renames the label declaration', () {
      final source =
          _loadFixture('function_body_with_yield_break_continue.dart');
      final body = parseFunctionBody(source);
      final labeled = body.statements[0] as LabeledStatementNode;

      final edit = FunctionBodyEditPlanner.renameStatementLabel(
        label: labeled.labels[0],
        newName: 'mainLoop',
      );
      final newSource = applySourceEdits(source, [edit]);
      // The label declaration is renamed; break/continue refs are NOT
      // updated (that's documented as caller-responsible).
      expect(newSource, contains('mainLoop:'));
      // Original refs remain pointing at the old name.
      expect(newSource, contains('continue outer;'));
    });

    test('moveStatement swaps two adjacent expression statements', () {
      const source = '''
void f() {
  a();
  b();
  c();
}
void a() {}
void b() {}
void c() {}
''';
      final body = parseFunctionBody(source);
      // Move statement at index 0 to index 1, producing: b, a, c.
      final edit = FunctionBodyEditPlanner.moveStatement(
        block: body.body,
        fromIndex: 0,
        toIndex: 1,
        source: source,
      );
      final newSource = applySourceEdits(source, [edit]);
      final reparsed = parseFunctionBody(newSource);
      expect(
        (reparsed.statements[0] as ExpressionStatementNode).expressionSource,
        equals('b()'),
      );
      expect(
        (reparsed.statements[1] as ExpressionStatementNode).expressionSource,
        equals('a()'),
      );
      expect(
        (reparsed.statements[2] as ExpressionStatementNode).expressionSource,
        equals('c()'),
      );
    });

    test('moveStatement from last to first reorders correctly', () {
      const source = '''
void f() {
  a();
  b();
  c();
}
void a() {}
void b() {}
void c() {}
''';
      final body = parseFunctionBody(source);
      // Move statement at index 2 to index 0, producing: c, a, b.
      final edit = FunctionBodyEditPlanner.moveStatement(
        block: body.body,
        fromIndex: 2,
        toIndex: 0,
        source: source,
      );
      final newSource = applySourceEdits(source, [edit]);
      final reparsed = parseFunctionBody(newSource);
      expect(
        (reparsed.statements[0] as ExpressionStatementNode).expressionSource,
        equals('c()'),
      );
      expect(
        (reparsed.statements[1] as ExpressionStatementNode).expressionSource,
        equals('a()'),
      );
      expect(
        (reparsed.statements[2] as ExpressionStatementNode).expressionSource,
        equals('b()'),
      );
    });

    test('moveStatement no-op when fromIndex == toIndex', () {
      const source = '''
void f() {
  a();
  b();
}
void a() {}
void b() {}
''';
      final body = parseFunctionBody(source);
      final edit = FunctionBodyEditPlanner.moveStatement(
        block: body.body,
        fromIndex: 1,
        toIndex: 1,
        source: source,
      );
      final newSource = applySourceEdits(source, [edit]);
      // Source-equivalent — `a();` and `b();` still in order.
      expect(newSource, contains('a();'));
      expect(newSource, contains('b();'));
      final reparsed = parseFunctionBody(newSource);
      expect(reparsed.statements, hasLength(2));
    });

    test('moveStatement throws on out-of-range indices', () {
      final source = _loadFixture('function_body_simple.dart');
      final body = parseFunctionBody(source);
      expect(
        () => FunctionBodyEditPlanner.moveStatement(
          block: body.body,
          fromIndex: 999,
          toIndex: 0,
          source: source,
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => FunctionBodyEditPlanner.moveStatement(
          block: body.body,
          fromIndex: 0,
          toIndex: -1,
          source: source,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('symbol-aware rename (M8.0h)', () {
    test('renames pattern variable AND its references in guard + body', () {
      const source = '''
String tier(int score) {
  switch (score) {
    case int n when n > 100:
      print('big: \$n');
      return 'big';
    default:
      return 'other';
  }
}
''';
      final body = parseFunctionBody(source);
      final sw = body.statements.first as SwitchStatementNode;
      final c0 = sw.members[0] as SwitchCaseNode;
      final pattern = c0.pattern as DeclaredVariablePatternNode;
      expect(pattern.name, equals('n'));

      final edits =
          FunctionBodyEditPlanner.renameDeclaredPatternVariableWithReferences(
        caseMember: c0,
        pattern: pattern,
        newName: 'value',
        source: source,
      );
      // 1 pattern + 1 guard ref + 2 body refs (one in print arg).
      expect(edits.length, greaterThanOrEqualTo(3));

      final newSource = applySourceEdits(source, edits);

      expect(newSource, contains('case int value when value > 100'));
      expect(newSource, contains(r"'big: $value'"));

      final reparsed = parseFunctionBody(newSource);
      final reparsedC0 = (reparsed.statements.first as SwitchStatementNode)
          .members[0] as SwitchCaseNode;
      final reparsedPattern = reparsedC0.pattern as DeclaredVariablePatternNode;
      expect(reparsedPattern.name, equals('value'));
      expect(reparsedC0.whenGuardSource, equals('value > 100'));
    });

    test('does NOT rewrite identifiers in string literals', () {
      const source = '''
String f(int x) {
  switch (x) {
    case int n:
      final tag = 'literal n';
      return '\$tag-\$n';
    default:
      return 'other';
  }
}
''';
      final body = parseFunctionBody(source);
      final sw = body.statements.first as SwitchStatementNode;
      final c0 = sw.members[0] as SwitchCaseNode;
      final pattern = c0.pattern as DeclaredVariablePatternNode;

      final edits =
          FunctionBodyEditPlanner.renameDeclaredPatternVariableWithReferences(
        caseMember: c0,
        pattern: pattern,
        newName: 'val',
        source: source,
      );
      final newSource = applySourceEdits(source, edits);

      // The string literal `'literal n'` is preserved verbatim.
      expect(newSource, contains("'literal n'"));
      // The `\$n` interpolation IS edited (n is a SimpleIdentifier).
      expect(newSource, contains(r'$val'));
      // Pattern is renamed.
      expect(newSource, contains('case int val:'));
    });
  });
}
