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
        parent: body,
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
        parent: body,
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
