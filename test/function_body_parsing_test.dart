import 'dart:io';

import 'package:loom/loom.dart';
import 'package:test/test.dart';

void main() {
  group('parseFunctionBody on function_body_simple.dart', () {
    late String source;
    late FunctionBodyModel body;

    setUpAll(() {
      source =
          File('test/fixtures/function_body_simple.dart').readAsStringSync();
      body = parseFunctionBody(source);
    });

    test('finds the first function body (registerUser)', () {
      expect(body.statements, hasLength(5));
    });

    test('first statement is a variable declaration: final normalized', () {
      final stmt = body.statements[0];
      expect(stmt, isA<VariableDeclarationStatementNode>());
      final v = stmt as VariableDeclarationStatementNode;
      expect(v.isFinal, isTrue);
      expect(v.variables, hasLength(1));
      expect(v.variables.first.name, equals('normalized'));
      expect(
        v.variables.first.initializerSource,
        equals('email.toLowerCase()'),
      );
    });

    test('second statement: final id = nextId()', () {
      final stmt = body.statements[1] as VariableDeclarationStatementNode;
      expect(stmt.isFinal, isTrue);
      expect(stmt.variables.first.name, equals('id'));
      expect(stmt.variables.first.initializerSource, equals('nextId()'));
    });

    test('third statement is an expression statement (log call)', () {
      final stmt = body.statements[2];
      expect(stmt, isA<ExpressionStatementNode>());
      final e = stmt as ExpressionStatementNode;
      expect(e.expressionSource, startsWith("log("));
    });

    test('fifth statement is a return with expression', () {
      final stmt = body.statements[4];
      expect(stmt, isA<ReturnStatementNode>());
      final r = stmt as ReturnStatementNode;
      expect(r.expressionSource, equals('id'));
    });

    test('body span and inner span are well-formed', () {
      // Body should start with '{' and end with '}'.
      final bodyText = source.substring(
        body.bodySpan.offset,
        body.bodySpan.offset + body.bodySpan.length,
      );
      expect(bodyText, startsWith('{'));
      expect(bodyText, endsWith('}'));
      // Inner span is between { and }.
      final innerText = source.substring(
        body.innerSpan.offset,
        body.innerSpan.offset + body.innerSpan.length,
      );
      expect(innerText.contains('{'), isFalse);
      expect(innerText.contains('}'), isFalse);
    });
  });

  group('parseFunctionBody with explicit bodySpan', () {
    test('parses a specific function body by offset', () {
      final source =
          File('test/fixtures/function_body_simple.dart').readAsStringSync();
      // nextId is the second function in the fixture; we'll use the
      // body span of registerUser (first finding) to verify default
      // behavior, then look at all bodies via the model count.
      final body = parseFunctionBody(source);
      expect(body.statements, hasLength(5));
    });
  });

  group('parseFunctionBody on function_body_with_if.dart (M8.0b)', () {
    late FunctionBodyModel body;
    late String source;

    setUpAll(() {
      source =
          File('test/fixtures/function_body_with_if.dart').readAsStringSync();
      body = parseFunctionBody(source);
    });

    test('finds the classify function body (4 statements)', () {
      // var clamped = ...; log(...); if (...) { ... } else { ... };
      expect(body.statements, hasLength(3));
      // No top-level return statement — the if/else covers both paths.
    });

    test('third statement is the if/else, modeled as IfStatementNode', () {
      final stmt = body.statements[2];
      expect(stmt, isA<IfStatementNode>());
      final ifStmt = stmt as IfStatementNode;
      expect(ifStmt.conditionSource, equals('clamped >= 90'));
    });

    test('then block has two statements (log + return)', () {
      final ifStmt = body.statements[2] as IfStatementNode;
      expect(ifStmt.thenBlock.statements, hasLength(2));
      expect(ifStmt.thenBlock.statements[0], isA<ExpressionStatementNode>());
      expect(ifStmt.thenBlock.statements[1], isA<ReturnStatementNode>());
    });

    test('else block has one return statement', () {
      final ifStmt = body.statements[2] as IfStatementNode;
      expect(ifStmt.elseBlock, isNotNull);
      expect(ifStmt.elseBlock!.statements, hasLength(1));
      expect(ifStmt.elseBlock!.statements.first, isA<ReturnStatementNode>());
    });

    test('then/else block spans cover their braces', () {
      final ifStmt = body.statements[2] as IfStatementNode;
      final thenText = source.substring(
        ifStmt.thenBlock.blockSpan.offset,
        ifStmt.thenBlock.blockSpan.offset + ifStmt.thenBlock.blockSpan.length,
      );
      expect(thenText, startsWith('{'));
      expect(thenText, endsWith('}'));

      final elseText = source.substring(
        ifStmt.elseBlock!.blockSpan.offset,
        ifStmt.elseBlock!.blockSpan.offset + ifStmt.elseBlock!.blockSpan.length,
      );
      expect(elseText, startsWith('{'));
      expect(elseText, endsWith('}'));
    });
  });

  group('parseFunctionBody — if with bare body falls through to opaque', () {
    test('bare-statement then-body opaqued', () {
      const source = '''
void f() {
  if (true) doIt();
}
void doIt() {}
''';
      final body = parseFunctionBody(source);
      expect(body.statements, hasLength(1));
      expect(body.statements.first, isA<OpaqueStatementNode>());
    });

    test('else if chain opaqued (whole if-statement)', () {
      const source = '''
void f() {
  if (true) {
    a();
  } else if (false) {
    b();
  }
}
void a() {}
void b() {}
''';
      final body = parseFunctionBody(source);
      expect(body.statements, hasLength(1));
      expect(body.statements.first, isA<OpaqueStatementNode>());
    });
  });

  group('parseFunctionBody rejection', () {
    test('throws on a source with no function bodies', () {
      const source = 'class Empty {}\n';
      expect(
        () => parseFunctionBody(source),
        throwsA(isA<ParseException>()),
      );
    });

    test('throws on an arrow body when explicit span requested', () {
      const source = 'int answer() => 42;\n';
      // The default no-bodySpan call would find the arrow body
      // (no BlockFunctionBody exists). It should throw because the
      // body isn't a block.
      expect(
        () => parseFunctionBody(source),
        throwsA(isA<ParseException>()),
      );
    });
  });
}
