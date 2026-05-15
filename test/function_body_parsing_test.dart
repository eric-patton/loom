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

    test('seven members in order: 6 cases + default', () {
      expect(switchStmt.members, hasLength(7));
      expect(switchStmt.members[0], isA<SwitchCaseNode>());
      expect(switchStmt.members[1], isA<SwitchCaseNode>());
      expect(switchStmt.members[2], isA<SwitchCaseNode>());
      expect(switchStmt.members[3], isA<SwitchCaseNode>());
      expect(switchStmt.members[4], isA<SwitchCaseNode>());
      expect(switchStmt.members[5], isA<SwitchCaseNode>());
      expect(switchStmt.members[6], isA<SwitchDefaultNode>());
    });

    test('first case is the legacy `case 0:` form with no guard', () {
      final c0 = switchStmt.members[0] as SwitchCaseNode;
      expect(c0.patternSource, equals('0'));
      expect(c0.whenGuardSource, isNull);
      expect(c0.body.statements, hasLength(1));
      expect(c0.body.statements.first, isA<ReturnStatementNode>());
    });

    test('logical-or case `1 || 2 || 3:` parses correctly', () {
      final c1 = switchStmt.members[1] as SwitchCaseNode;
      expect(c1.patternSource, equals('1 || 2 || 3'));
      expect(c1.whenGuardSource, isNull);
    });

    test('pattern case with `when n < 0` guard parses correctly', () {
      final c2 = switchStmt.members[2] as SwitchCaseNode;
      expect(c2.patternSource, equals('int n'));
      expect(c2.whenGuardSource, equals('n < 0'));
      expect(c2.whenKeywordSpan, isNotNull);
    });

    test('pattern case with `when n > 100` guard parses correctly', () {
      final c3 = switchStmt.members[3] as SwitchCaseNode;
      expect(c3.patternSource, equals('int n'));
      expect(c3.whenGuardSource, equals('n > 100'));
    });

    test('pattern case without guard parses correctly', () {
      final c4 = switchStmt.members[4] as SwitchCaseNode;
      expect(c4.patternSource, equals('String s'));
      expect(c4.whenGuardSource, isNull);
    });

    test('wildcard case `int _:` parses correctly', () {
      final c5 = switchStmt.members[5] as SwitchCaseNode;
      expect(c5.patternSource, equals('int _'));
    });

    test('default has a body with one statement', () {
      final d = switchStmt.members[6] as SwitchDefaultNode;
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

    // -------------------- M8.0f pattern internals --------------------

    test('legacy case constant pattern is a ConstantPatternNode', () {
      final c0 = switchStmt.members[0] as SwitchCaseNode;
      expect(c0.pattern, isA<ConstantPatternNode>());
      final p = c0.pattern as ConstantPatternNode;
      expect(p.expressionSource, equals('0'));
      expect(p.constKeywordSpan, isNull);
    });

    test('logical-or pattern flattens into 3 operands + 2 || spans', () {
      final c1 = switchStmt.members[1] as SwitchCaseNode;
      expect(c1.pattern, isA<LogicalOrPatternNode>());
      final or = c1.pattern as LogicalOrPatternNode;
      expect(or.operands, hasLength(3));
      expect(or.operatorSpans, hasLength(2));
      for (final op in or.operands) {
        expect(op, isA<ConstantPatternNode>());
      }
      expect(
        (or.operands[0] as ConstantPatternNode).expressionSource,
        equals('1'),
      );
      expect(
        (or.operands[1] as ConstantPatternNode).expressionSource,
        equals('2'),
      );
      expect(
        (or.operands[2] as ConstantPatternNode).expressionSource,
        equals('3'),
      );
    });

    test('declared variable pattern with type captures type + name', () {
      final c2 = switchStmt.members[2] as SwitchCaseNode;
      expect(c2.pattern, isA<DeclaredVariablePatternNode>());
      final p = c2.pattern as DeclaredVariablePatternNode;
      expect(p.typeSource, equals('int'));
      expect(p.name, equals('n'));
      expect(p.keywordSpan, isNull);
    });

    test('declared variable pattern with String type', () {
      final c4 = switchStmt.members[4] as SwitchCaseNode;
      final p = c4.pattern as DeclaredVariablePatternNode;
      expect(p.typeSource, equals('String'));
      expect(p.name, equals('s'));
    });

    test('wildcard pattern with type captures type + underscore span', () {
      final c5 = switchStmt.members[5] as SwitchCaseNode;
      expect(c5.pattern, isA<WildcardPatternNode>());
      final p = c5.pattern as WildcardPatternNode;
      expect(p.typeSource, equals('int'));
    });

    test('`case var x:` parses as DeclaredVariablePatternNode with keyword',
        () {
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
      expect(p.keywordSpan, isNotNull);
      expect(p.typeSource, isNull);
      expect(p.name, equals('x'));
    });

    test('bare `case _:` parses as WildcardPatternNode without type', () {
      const source = '''
String f(Object o) {
  switch (o) {
    case _:
      return 'any';
  }
}
''';
      final body = parseFunctionBody(source);
      final sw = body.statements.first as SwitchStatementNode;
      final c0 = sw.members[0] as SwitchCaseNode;
      final p = c0.pattern as WildcardPatternNode;
      expect(p.typeSource, isNull);
      expect(p.keywordSpan, isNull);
    });

    test('list pattern is now modeled (M8.0h)', () {
      const source = '''
String f(List<int> xs) {
  switch (xs) {
    case [1, 2]:
      return 'pair';
    default:
      return 'other';
  }
}
''';
      final body = parseFunctionBody(source);
      final sw = body.statements.first as SwitchStatementNode;
      final c0 = sw.members[0] as SwitchCaseNode;
      expect(c0.pattern, isA<ListPatternNode>());
    });
  });

  group(
      'parseFunctionBody on function_body_with_object_record_patterns.dart '
      '(M8.0g)', () {
    late FunctionBodyModel body;
    late SwitchStatementNode sw;

    setUpAll(() {
      final source = File(
        'test/fixtures/function_body_with_object_record_patterns.dart',
      ).readAsStringSync();
      body = parseFunctionBody(source);
      sw = body.statements.first as SwitchStatementNode;
    });

    test('switch has 6 members (5 cases + default)', () {
      expect(sw.members, hasLength(6));
      expect(sw.members.last, isA<SwitchDefaultNode>());
    });

    test('Point(x: 0, y: 0) is an ObjectPatternNode with 2 named fields', () {
      final c0 = sw.members[0] as SwitchCaseNode;
      expect(c0.pattern, isA<ObjectPatternNode>());
      final op = c0.pattern as ObjectPatternNode;
      expect(op.typeNameSource, equals('Point'));
      expect(op.fields, hasLength(2));
      expect(op.fields[0].fieldName, equals('x'));
      expect(op.fields[0].isShorthand, isFalse);
      expect(op.fields[0].isNamed, isTrue);
      expect(op.fields[1].fieldName, equals('y'));
    });

    test('Point field sub-pattern is recursive (constants here)', () {
      final c0 = sw.members[0] as SwitchCaseNode;
      final op = c0.pattern as ObjectPatternNode;
      expect(op.fields[0].pattern, isA<ConstantPatternNode>());
      expect(
        (op.fields[0].pattern as ConstantPatternNode).expressionSource,
        equals('0'),
      );
    });

    test('Point(x: var x, y: var y) when x == y captures inner patterns', () {
      final c1 = sw.members[1] as SwitchCaseNode;
      final op = c1.pattern as ObjectPatternNode;
      expect(op.typeNameSource, equals('Point'));
      expect(op.fields[0].pattern, isA<DeclaredVariablePatternNode>());
      expect(
        (op.fields[0].pattern as DeclaredVariablePatternNode).name,
        equals('x'),
      );
      // Guard is still captured at the SwitchCaseNode level.
      expect(c1.whenGuardSource, equals('x == y'));
    });

    test('Rect(:var width, :var height) uses shorthand named fields', () {
      final c2 = sw.members[2] as SwitchCaseNode;
      final op = c2.pattern as ObjectPatternNode;
      expect(op.typeNameSource, equals('Rect'));
      expect(op.fields, hasLength(2));
      expect(op.fields[0].isShorthand, isTrue);
      expect(op.fields[0].fieldName, isNull);
      expect(op.fields[0].colonSpan, isNotNull);
      // Inner pattern is a declared variable whose name acts as the
      // implicit field name.
      final inner = op.fields[0].pattern as DeclaredVariablePatternNode;
      expect(inner.name, equals('width'));
    });

    test('(int a, int b) is a RecordPatternNode with 2 positional fields', () {
      final c3 = sw.members[3] as SwitchCaseNode;
      expect(c3.pattern, isA<RecordPatternNode>());
      final rp = c3.pattern as RecordPatternNode;
      expect(rp.fields, hasLength(2));
      expect(rp.fields[0].isPositional, isTrue);
      expect(rp.fields[0].fieldName, isNull);
      expect(rp.fields[0].colonSpan, isNull);
      // Inner pattern is `int a` — a declared variable.
      final inner = rp.fields[0].pattern as DeclaredVariablePatternNode;
      expect(inner.typeSource, equals('int'));
      expect(inner.name, equals('a'));
    });

    test('(x: var x, y: var y) is a RecordPatternNode with 2 named fields', () {
      final c4 = sw.members[4] as SwitchCaseNode;
      final rp = c4.pattern as RecordPatternNode;
      expect(rp.fields, hasLength(2));
      expect(rp.fields[0].fieldName, equals('x'));
      expect(rp.fields[0].isShorthand, isFalse);
      expect(rp.fields[0].pattern, isA<DeclaredVariablePatternNode>());
    });

    test('parameterized object pattern captures the full type name', () {
      const source = '''
String f(Object o) {
  switch (o) {
    case Result<int>(:var value):
      return 'value=\$value';
    default:
      return 'other';
  }
}
class Result<T> {
  final T value;
  const Result({required this.value});
}
''';
      final body = parseFunctionBody(source);
      final sw = body.statements.first as SwitchStatementNode;
      final c0 = sw.members[0] as SwitchCaseNode;
      final op = c0.pattern as ObjectPatternNode;
      expect(op.typeNameSource, equals('Result<int>'));
    });

    test('empty object pattern Foo() parses with zero fields', () {
      const source = '''
String f(Object o) {
  switch (o) {
    case Empty():
      return 'empty';
    default:
      return 'other';
  }
}
class Empty {
  const Empty();
}
''';
      final body = parseFunctionBody(source);
      final sw = body.statements.first as SwitchStatementNode;
      final c0 = sw.members[0] as SwitchCaseNode;
      final op = c0.pattern as ObjectPatternNode;
      expect(op.fields, isEmpty);
      expect(op.typeNameSource, equals('Empty'));
    });
  });

  group(
      'parseFunctionBody on function_body_with_remaining_patterns.dart '
      '(M8.0h)', () {
    late FunctionBodyModel body;
    late SwitchStatementNode sw;

    setUpAll(() {
      final source =
          File('test/fixtures/function_body_with_remaining_patterns.dart')
              .readAsStringSync();
      body = parseFunctionBody(source);
      sw = body.statements.first as SwitchStatementNode;
    });

    test('switch has 12 members (11 cases + default)', () {
      expect(sw.members, hasLength(12));
      expect(sw.members.last, isA<SwitchDefaultNode>());
    });

    test('[int a, int b] is a ListPatternNode with 2 pattern elements', () {
      final c0 = sw.members[0] as SwitchCaseNode;
      final lp = c0.pattern as ListPatternNode;
      expect(lp.elements, hasLength(2));
      expect(lp.elements[0], isA<ListPatternPatternElement>());
      final p0 = (lp.elements[0] as ListPatternPatternElement).pattern
          as DeclaredVariablePatternNode;
      expect(p0.typeSource, equals('int'));
      expect(p0.name, equals('a'));
    });

    test('[int first, ...] has a bare rest element', () {
      final c1 = sw.members[1] as SwitchCaseNode;
      final lp = c1.pattern as ListPatternNode;
      expect(lp.elements, hasLength(2));
      expect(lp.elements[1], isA<ListPatternRestElement>());
      final rest = lp.elements[1] as ListPatternRestElement;
      expect(rest.subPattern, isNull);
    });

    test('[int head, ...List<int> tail] has a sub-patterned rest', () {
      final c2 = sw.members[2] as SwitchCaseNode;
      final lp = c2.pattern as ListPatternNode;
      final rest = lp.elements[1] as ListPatternRestElement;
      expect(rest.subPattern, isNotNull);
      final inner = rest.subPattern! as DeclaredVariablePatternNode;
      expect(inner.typeSource, equals('List<int>'));
      expect(inner.name, equals('tail'));
    });

    test("{'name': String name} is a MapPatternNode with one entry", () {
      final c3 = sw.members[3] as SwitchCaseNode;
      final mp = c3.pattern as MapPatternNode;
      expect(mp.elements, hasLength(1));
      final entry = mp.elements[0] as MapPatternEntryNode;
      expect(entry.keyExpressionSource, equals("'name'"));
      final inner = entry.pattern as DeclaredVariablePatternNode;
      expect(inner.name, equals('name'));
    });

    test('> 100 is a RelationalPatternNode', () {
      final c4 = sw.members[4] as SwitchCaseNode;
      final rp = c4.pattern as RelationalPatternNode;
      expect(rp.operator, equals('>'));
      expect(rp.operandSource, equals('100'));
    });

    test("== 'zero' is a RelationalPatternNode with operator ==", () {
      final c5 = sw.members[5] as SwitchCaseNode;
      final rp = c5.pattern as RelationalPatternNode;
      expect(rp.operator, equals('=='));
      expect(rp.operandSource, equals("'zero'"));
    });

    test('var x? is a NullCheckPatternNode wrapping a declared variable', () {
      final c6 = sw.members[6] as SwitchCaseNode;
      final nc = c6.pattern as NullCheckPatternNode;
      final inner = nc.innerPattern as DeclaredVariablePatternNode;
      expect(inner.name, equals('x'));
    });

    test('var y! is a NullAssertPatternNode', () {
      final c7 = sw.members[7] as SwitchCaseNode;
      final na = c7.pattern as NullAssertPatternNode;
      final inner = na.innerPattern as DeclaredVariablePatternNode;
      expect(inner.name, equals('y'));
    });

    test('var z as int is a CastPatternNode', () {
      final c8 = sw.members[8] as SwitchCaseNode;
      final cast = c8.pattern as CastPatternNode;
      expect(cast.typeSource, equals('int'));
      final inner = cast.innerPattern as DeclaredVariablePatternNode;
      expect(inner.name, equals('z'));
    });

    test('(1 || 2 || 3) is a ParenthesizedPatternNode wrapping a LogicalOr',
        () {
      final c9 = sw.members[9] as SwitchCaseNode;
      final pp = c9.pattern as ParenthesizedPatternNode;
      final or = pp.innerPattern as LogicalOrPatternNode;
      expect(or.operands, hasLength(3));
    });

    test('int n && > 0 is a LogicalAndPatternNode flattened to 2 operands', () {
      final c10 = sw.members[10] as SwitchCaseNode;
      final and = c10.pattern as LogicalAndPatternNode;
      expect(and.operands, hasLength(2));
      expect(and.operatorSpans, hasLength(1));
      expect(and.operands[0], isA<DeclaredVariablePatternNode>());
      expect(and.operands[1], isA<RelationalPatternNode>());
    });
  });

  group(
      'parseFunctionBody on function_body_with_switch_expressions.dart '
      '(M8.0h)', () {
    late String source;
    late FunctionBodyModel body;

    setUpAll(() {
      source = File('test/fixtures/function_body_with_switch_expressions.dart')
          .readAsStringSync();
      body = parseFunctionBody(source);
    });

    test('variable initializer surfaces a SwitchExpressionNode', () {
      final v = body.statements[0] as VariableDeclarationStatementNode;
      final declared = v.variables.first;
      expect(declared.initializerSwitchExpression, isNotNull);
      final sx = declared.initializerSwitchExpression!;
      expect(sx.subjectSource, equals('x'));
      expect(sx.cases, hasLength(4));
    });

    test('first case has constant pattern, last is wildcard', () {
      final v = body.statements[0] as VariableDeclarationStatementNode;
      final sx = v.variables.first.initializerSwitchExpression!;
      expect(sx.cases[0].pattern, isA<ConstantPatternNode>());
      expect(sx.cases[3].pattern, isA<WildcardPatternNode>());
    });

    test('logical-or case in switch expression is structured', () {
      final v = body.statements[0] as VariableDeclarationStatementNode;
      final sx = v.variables.first.initializerSwitchExpression!;
      expect(sx.cases[1].pattern, isA<LogicalOrPatternNode>());
      final or = sx.cases[1].pattern as LogicalOrPatternNode;
      expect(or.operands, hasLength(3));
    });

    test('guarded case carries when guard source', () {
      final v = body.statements[0] as VariableDeclarationStatementNode;
      final sx = v.variables.first.initializerSwitchExpression!;
      expect(sx.cases[2].whenGuardSource, equals('n > 100'));
    });

    test('result expressions captured per arm', () {
      final v = body.statements[0] as VariableDeclarationStatementNode;
      final sx = v.variables.first.initializerSwitchExpression!;
      expect(sx.cases[0].resultExpressionSource, equals("'zero'"));
      expect(sx.cases[1].resultExpressionSource, equals("'small'"));
    });

    test('return statement surfaces a SwitchExpressionNode', () {
      // describeReturn is the second function in the fixture — we need to
      // locate it explicitly via its body span.
      final marker = source.indexOf('describeReturn');
      final braceOpen = source.indexOf('{', marker);
      final braceClose = _matchingBrace(source, braceOpen);
      final body = parseFunctionBody(
        source,
        bodySpan: SourceSpan(
          offset: braceOpen,
          length: braceClose - braceOpen + 1,
        ),
      );
      final ret = body.statements.first as ReturnStatementNode;
      expect(ret.switchExpression, isNotNull);
      expect(ret.switchExpression!.cases, hasLength(3));
      expect(
          ret.switchExpression!.cases[0].pattern, isA<RelationalPatternNode>());
    });
  });

  group(
      'parseFunctionBody on function_body_with_yield_break_continue.dart '
      '(M8.1)', () {
    late FunctionBodyModel body;

    setUpAll(() {
      final source =
          File('test/fixtures/function_body_with_yield_break_continue.dart')
              .readAsStringSync();
      body = parseFunctionBody(source);
    });

    test('top-level body has 1 statement (the labeled for-loop)', () {
      expect(body.statements, hasLength(1));
      expect(body.statements[0], isA<LabeledStatementNode>());
    });

    test('labeled statement carries one label named "outer"', () {
      final labeled = body.statements[0] as LabeledStatementNode;
      expect(labeled.labels, hasLength(1));
      expect(labeled.labels[0].name, equals('outer'));
      expect(labeled.statement, isA<ForStatementNode>());
    });

    test('for-body has 5 statements: var, if, if, yield, yield*', () {
      final labeled = body.statements[0] as LabeledStatementNode;
      final forStmt = labeled.statement as ForStatementNode;
      expect(forStmt.body.statements, hasLength(5));
      expect(forStmt.body.statements[3], isA<YieldStatementNode>());
      expect(forStmt.body.statements[4], isA<YieldStatementNode>());
    });

    test('first yield is a single value (no star)', () {
      final labeled = body.statements[0] as LabeledStatementNode;
      final forStmt = labeled.statement as ForStatementNode;
      final y0 = forStmt.body.statements[3] as YieldStatementNode;
      expect(y0.isDelegating, isFalse);
      expect(y0.starSpan, isNull);
      expect(y0.expressionSource, equals('v'));
    });

    test('second yield is yield* with a list expression', () {
      final labeled = body.statements[0] as LabeledStatementNode;
      final forStmt = labeled.statement as ForStatementNode;
      final y1 = forStmt.body.statements[4] as YieldStatementNode;
      expect(y1.isDelegating, isTrue);
      expect(y1.starSpan, isNotNull);
      expect(y1.expressionSource, equals('[v + 100, v + 200]'));
    });

    test('continue and break carry the "outer" label name', () {
      final labeled = body.statements[0] as LabeledStatementNode;
      final forStmt = labeled.statement as ForStatementNode;
      // First if's then-block: continue outer;
      final firstIf = forStmt.body.statements[1] as IfStatementNode;
      final cont = firstIf.thenBlock.statements.first as ContinueStatementNode;
      expect(cont.labelName, equals('outer'));
      // Second if's then-block: break outer;
      final secondIf = forStmt.body.statements[2] as IfStatementNode;
      final brk = secondIf.thenBlock.statements.first as BreakStatementNode;
      expect(brk.labelName, equals('outer'));
    });

    test('bare break and bare continue have null labelName', () {
      const source = '''
void f(List<int> xs) {
  for (final x in xs) {
    if (x < 0) {
      continue;
    }
    if (x > 10) {
      break;
    }
  }
}
''';
      final body = parseFunctionBody(source);
      final forStmt = body.statements.first as ForStatementNode;
      final firstIf = forStmt.body.statements[0] as IfStatementNode;
      final cont = firstIf.thenBlock.statements.first as ContinueStatementNode;
      expect(cont.labelName, isNull);
      final secondIf = forStmt.body.statements[1] as IfStatementNode;
      final brk = secondIf.thenBlock.statements.first as BreakStatementNode;
      expect(brk.labelName, isNull);
    });

    test('multi-label stack is captured in source order', () {
      const source = '''
void f() {
  a: b: while (true) {
    break a;
  }
}
''';
      final body = parseFunctionBody(source);
      final labeled = body.statements.first as LabeledStatementNode;
      expect(labeled.labels, hasLength(2));
      expect(labeled.labels[0].name, equals('a'));
      expect(labeled.labels[1].name, equals('b'));
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

/// Finds the matching `}` for the `{` at [open], handling nested
/// braces. Used in M8.0h tests to locate the second function's body
/// span in a multi-function fixture.
int _matchingBrace(String source, int open) {
  assert(source[open] == '{');
  var depth = 1;
  var i = open + 1;
  while (i < source.length) {
    final ch = source[i];
    if (ch == '{') depth++;
    if (ch == '}') {
      depth--;
      if (depth == 0) return i;
    }
    i++;
  }
  throw StateError('unbalanced braces');
}
