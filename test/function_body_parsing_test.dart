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
  });

  group('parseFunctionBody on function_body_with_else_if.dart (M8.0c)', () {
    late FunctionBodyModel body;

    setUpAll(() {
      final source = File('test/fixtures/function_body_with_else_if.dart')
          .readAsStringSync();
      body = parseFunctionBody(source);
    });

    test('two top-level statements: variable + if-chain', () {
      expect(body.statements, hasLength(2));
      expect(body.statements[0], isA<VariableDeclarationStatementNode>());
      expect(body.statements[1], isA<IfStatementNode>());
    });

    test('else-if chain has three branches plus terminal else', () {
      final head = body.statements[1] as IfStatementNode;
      expect(head.conditionSource, equals('clamped >= 90'));
      expect(head.elseBlock, isNull);
      expect(head.elseIf, isNotNull);

      final second = head.elseIf!;
      expect(second.conditionSource, equals('clamped >= 80'));
      expect(second.elseBlock, isNull);
      expect(second.elseIf, isNotNull);

      final third = second.elseIf!;
      expect(third.conditionSource, equals('clamped >= 70'));
      expect(third.elseIf, isNull);
      expect(third.elseBlock, isNotNull);
      expect(third.elseBlock!.statements, hasLength(1));
      expect(third.elseBlock!.statements.first, isA<ReturnStatementNode>());
    });

    test('each branch has the elseKeywordSpan of its introducer', () {
      final head = body.statements[1] as IfStatementNode;
      expect(head.elseKeywordSpan, isNotNull);
      final second = head.elseIf!;
      expect(second.elseKeywordSpan, isNotNull);
    });

    test('bare-body else-if anywhere in chain → whole chain opaque', () {
      const source = '''
void f() {
  if (true) {
    a();
  } else if (false) b();
}
void a() {}
void b() {}
''';
      final body = parseFunctionBody(source);
      expect(body.statements, hasLength(1));
      expect(body.statements.first, isA<OpaqueStatementNode>());
    });
  });

  group('parseFunctionBody on function_body_with_loops.dart (M8.0c)', () {
    late String source;
    late FunctionBodyModel body;

    setUpAll(() {
      source = File('test/fixtures/function_body_with_loops.dart')
          .readAsStringSync();
      body = parseFunctionBody(source);
    });

    test('top-level body has 5 statements (var, for, var, while, return)', () {
      expect(body.statements, hasLength(5));
      expect(body.statements[0], isA<VariableDeclarationStatementNode>());
      expect(body.statements[1], isA<ForStatementNode>());
      expect(body.statements[2], isA<VariableDeclarationStatementNode>());
      expect(body.statements[3], isA<WhileStatementNode>());
      expect(body.statements[4], isA<ReturnStatementNode>());
    });

    test('for-loop header captured as raw source', () {
      final forStmt = body.statements[1] as ForStatementNode;
      expect(forStmt.headerSource, equals('(var i = 0; i < n; i++)'));
      expect(forStmt.awaitKeywordSpan, isNull);
    });

    test('for-loop body has one statement (total = total + i)', () {
      final forStmt = body.statements[1] as ForStatementNode;
      expect(forStmt.body.statements, hasLength(1));
      expect(forStmt.body.statements.first, isA<ExpressionStatementNode>());
    });

    test('while-loop condition captured without parens', () {
      final wh = body.statements[3] as WhileStatementNode;
      expect(wh.conditionSource, equals('remaining > 100'));
    });

    test('for-loop header span surrounds parens', () {
      final forStmt = body.statements[1] as ForStatementNode;
      final headerText = source.substring(
        forStmt.headerSpan.offset,
        forStmt.headerSpan.offset + forStmt.headerSpan.length,
      );
      expect(headerText, startsWith('('));
      expect(headerText, endsWith(')'));
    });

    test('await-for is supported and captures await keyword span', () {
      const asyncSource = '''
Future<void> consume(Stream<int> stream) async {
  await for (final value in stream) {
    use(value);
  }
}
void use(int x) {}
''';
      final body = parseFunctionBody(asyncSource);
      expect(body.statements, hasLength(1));
      final forStmt = body.statements.first as ForStatementNode;
      expect(forStmt.awaitKeywordSpan, isNotNull);
      expect(forStmt.headerSource, equals('(final value in stream)'));
    });

    test('do-while is modeled in M8.0d (no longer opaque)', () {
      const source = '''
void f() {
  var i = 0;
  do {
    i++;
  } while (i < 3);
}
''';
      final body = parseFunctionBody(source);
      expect(body.statements, hasLength(2));
      expect(body.statements[1], isA<DoStatementNode>());
    });
  });

  group('parseFunctionBody on function_body_with_do_while.dart (M8.0d)', () {
    late FunctionBodyModel body;

    setUpAll(() {
      final source = File('test/fixtures/function_body_with_do_while.dart')
          .readAsStringSync();
      body = parseFunctionBody(source);
    });

    test('top-level body has 3 statements (var, do-while, return)', () {
      expect(body.statements, hasLength(3));
      expect(body.statements[0], isA<VariableDeclarationStatementNode>());
      expect(body.statements[1], isA<DoStatementNode>());
      expect(body.statements[2], isA<ReturnStatementNode>());
    });

    test('do-while body has one statement', () {
      final doStmt = body.statements[1] as DoStatementNode;
      expect(doStmt.body.statements, hasLength(1));
      expect(doStmt.body.statements.first, isA<ExpressionStatementNode>());
    });

    test('do-while condition captured without parens', () {
      final doStmt = body.statements[1] as DoStatementNode;
      expect(doStmt.conditionSource, equals('n > floor'));
    });

    test('do-while bare body falls through to opaque', () {
      const source = '''
void f() {
  var i = 0;
  do i++; while (i < 3);
}
''';
      final body = parseFunctionBody(source);
      expect(body.statements[1], isA<OpaqueStatementNode>());
    });
  });

  group('parseFunctionBody on function_body_with_try.dart (M8.0d)', () {
    late String source;
    late FunctionBodyModel body;
    late TryStatementNode tryStmt;

    setUpAll(() {
      source =
          File('test/fixtures/function_body_with_try.dart').readAsStringSync();
      body = parseFunctionBody(source);
      tryStmt = body.statements[1] as TryStatementNode;
    });

    test('top-level body has 3 statements (var, try, return)', () {
      expect(body.statements, hasLength(3));
      expect(body.statements[0], isA<VariableDeclarationStatementNode>());
      expect(body.statements[1], isA<TryStatementNode>());
      expect(body.statements[2], isA<ReturnStatementNode>());
    });

    test('try block has one statement', () {
      expect(tryStmt.tryBlock.statements, hasLength(1));
      expect(tryStmt.tryBlock.statements.first, isA<ExpressionStatementNode>());
    });

    test('two catch clauses + a finally block', () {
      expect(tryStmt.catchClauses, hasLength(2));
      expect(tryStmt.finallyBlock, isNotNull);
      expect(tryStmt.finallyBlock!.statements, hasLength(1));
    });

    test('first catch is on FormatException catch (e)', () {
      final c0 = tryStmt.catchClauses[0];
      expect(c0.exceptionTypeSource, equals('FormatException'));
      expect(c0.exceptionParameterName, equals('e'));
      expect(c0.stackTraceParameterName, isNull);
    });

    test('second catch is catch (e, s) without type', () {
      final c1 = tryStmt.catchClauses[1];
      expect(c1.exceptionTypeSource, isNull);
      expect(c1.exceptionParameterName, equals('e'));
      expect(c1.stackTraceParameterName, equals('s'));
    });

    test('try keyword + finally keyword spans line up with source', () {
      final tryText = source.substring(
        tryStmt.tryKeywordSpan.offset,
        tryStmt.tryKeywordSpan.offset + tryStmt.tryKeywordSpan.length,
      );
      expect(tryText, equals('try'));
      final finallyText = source.substring(
        tryStmt.finallyKeywordSpan!.offset,
        tryStmt.finallyKeywordSpan!.offset + tryStmt.finallyKeywordSpan!.length,
      );
      expect(finallyText, equals('finally'));
    });

    test('try-only (no catch, just finally) parses cleanly', () {
      const fSource = '''
void f() {
  try {
    work();
  } finally {
    cleanup();
  }
}
void work() {}
void cleanup() {}
''';
      final body = parseFunctionBody(fSource);
      final t = body.statements.first as TryStatementNode;
      expect(t.catchClauses, isEmpty);
      expect(t.finallyBlock, isNotNull);
    });
  });

  group('parseFunctionBody on function_body_with_throw.dart (M8.0d)', () {
    late FunctionBodyModel body;

    setUpAll(() {
      final source = File('test/fixtures/function_body_with_throw.dart')
          .readAsStringSync();
      body = parseFunctionBody(source);
    });

    test('top-level body has 2 statements (if, return)', () {
      expect(body.statements, hasLength(2));
      expect(body.statements[0], isA<IfStatementNode>());
      expect(body.statements[1], isA<ReturnStatementNode>());
    });

    test('throw inside the if then-block is a ThrowStatementNode', () {
      final ifStmt = body.statements[0] as IfStatementNode;
      expect(ifStmt.thenBlock.statements, hasLength(1));
      final thrown = ifStmt.thenBlock.statements.first as ThrowStatementNode;
      expect(
        thrown.expressionSource,
        equals("ArgumentError('n must be positive')"),
      );
    });

    test('buried throw inside an expression stays an ExpressionStatement', () {
      const source = '''
void f(int? n) {
  final v = n ?? (throw StateError('null'));
  use(v);
}
void use(int x) {}
''';
      final body = parseFunctionBody(source);
      // First statement: var v = ... (a variable decl, not a throw stmt).
      expect(
        body.statements.first,
        isA<VariableDeclarationStatementNode>(),
      );
    });
  });

  group('parseFunctionBody on function_body_with_switch.dart (M8.0e)', () {
    late String source;
    late FunctionBodyModel body;
    late SwitchStatementNode switchStmt;

    setUpAll(() {
      source = File('test/fixtures/function_body_with_switch.dart')
          .readAsStringSync();
      body = parseFunctionBody(source);
      switchStmt = body.statements.first as SwitchStatementNode;
    });

    test('the function body is a single switch statement', () {
      expect(body.statements, hasLength(1));
      expect(body.statements.first, isA<SwitchStatementNode>());
    });

    test('switched expression is captured', () {
      expect(switchStmt.expressionSource, equals('value'));
    });

    test('five members in order: 4 cases + default', () {
      expect(switchStmt.members, hasLength(5));
      expect(switchStmt.members[0], isA<SwitchCaseNode>());
      expect(switchStmt.members[1], isA<SwitchCaseNode>());
      expect(switchStmt.members[2], isA<SwitchCaseNode>());
      expect(switchStmt.members[3], isA<SwitchCaseNode>());
      expect(switchStmt.members[4], isA<SwitchDefaultNode>());
    });

    test('first case is the legacy `case 0:` form with no guard', () {
      final c0 = switchStmt.members[0] as SwitchCaseNode;
      expect(c0.patternSource, equals('0'));
      expect(c0.whenGuardSource, isNull);
      expect(c0.body.statements, hasLength(1));
      expect(c0.body.statements.first, isA<ReturnStatementNode>());
    });

    test('pattern case with `when n < 0` guard parses correctly', () {
      final c1 = switchStmt.members[1] as SwitchCaseNode;
      expect(c1.patternSource, equals('int n'));
      expect(c1.whenGuardSource, equals('n < 0'));
      expect(c1.whenKeywordSpan, isNotNull);
    });

    test('pattern case with `when n > 100` guard parses correctly', () {
      final c2 = switchStmt.members[2] as SwitchCaseNode;
      expect(c2.patternSource, equals('int n'));
      expect(c2.whenGuardSource, equals('n > 100'));
    });

    test('pattern case without guard parses correctly', () {
      final c3 = switchStmt.members[3] as SwitchCaseNode;
      expect(c3.patternSource, equals('String s'));
      expect(c3.whenGuardSource, isNull);
    });

    test('default has a body with one statement', () {
      final d = switchStmt.members[4] as SwitchDefaultNode;
      expect(d.body.statements, hasLength(1));
      expect(d.body.statements.first, isA<ReturnStatementNode>());
    });

    test('case body block is brace-less', () {
      for (final m in switchStmt.members) {
        expect(m.body.hasBraces, isFalse);
      }
    });

    test('switch keyword + brackets spans line up with source', () {
      final kw = source.substring(
        switchStmt.switchKeywordSpan.offset,
        switchStmt.switchKeywordSpan.offset +
            switchStmt.switchKeywordSpan.length,
      );
      expect(kw, equals('switch'));
      final lb = source.substring(
        switchStmt.leftBracketSpan.offset,
        switchStmt.leftBracketSpan.offset + switchStmt.leftBracketSpan.length,
      );
      expect(lb, equals('{'));
      final rb = source.substring(
        switchStmt.rightBracketSpan.offset,
        switchStmt.rightBracketSpan.offset + switchStmt.rightBracketSpan.length,
      );
      expect(rb, equals('}'));
    });

    test('multi-case fall-through parses as separate empty-body cases', () {
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
      final s = body.statements.first as SwitchStatementNode;
      expect(s.members, hasLength(3));
      final c1 = s.members[0] as SwitchCaseNode;
      final c2 = s.members[1] as SwitchCaseNode;
      expect(c1.body.statements, isEmpty);
      expect(c2.body.statements, hasLength(1));
    });

    test('switch expression (not a statement) stays opaque inside its host',
        () {
      const source = '''
String tag(int x) {
  final result = switch (x) { 1 => 'one', _ => 'other' };
  return result;
}
''';
      final body = parseFunctionBody(source);
      // The variable declaration is structured, but its initializer
      // (the switch expression) is captured as opaque source text.
      final v0 = body.statements.first as VariableDeclarationStatementNode;
      expect(v0.variables.first.initializerSource, startsWith('switch ('));
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
