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
}
