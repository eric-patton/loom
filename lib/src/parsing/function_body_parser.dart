import 'package:analyzer/dart/analysis/utilities.dart';
// Hide analyzer's `ClassMember` (clashes with the loom-side sealed
// type) and `PatternField` (clashes with the loom-side compound-pattern
// field class — we still need the analyzer's via a prefixed import).
import 'package:analyzer/dart/ast/ast.dart' hide ClassMember, PatternField;
import 'package:analyzer/dart/ast/ast.dart' as ast show PatternField;
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../model/function_body.dart';
import '../model/source_span.dart';
import 'base_visitor.dart' show ParseException;

/// Parses a Dart function body (the `{ ... }` block of a method,
/// constructor, top-level function, or anonymous closure) into a
/// `FunctionBodyModel`.
///
/// When `bodySpan` is null, the parser walks the file and returns the
/// FIRST `BlockFunctionBody` it finds (depth-first, so nested closures
/// inside a top-level function aren't preferred over the top-level
/// function's own body). Pass an explicit `bodySpan` (from a
/// `ClassMethodNode.bodySpan` or similar) to parse a specific body.
///
/// Throws `ParseException` when:
///   * No `BlockFunctionBody` is found at all.
///   * The body at the requested span is an `ExpressionFunctionBody`
///     (arrow function `=> expr;`) — M8.0a only models block bodies.
///   * The body at the requested span is `EmptyFunctionBody` (`;`).
FunctionBodyModel parseFunctionBody(String source, {SourceSpan? bodySpan}) {
  final result = parseString(content: source, throwIfDiagnostics: false);
  final unit = result.unit;
  final diagnostics = <ParseDiagnostic>[
    for (final error in result.errors)
      ParseDiagnostic(
        span: SourceSpan(offset: error.offset, length: error.length),
        message: error.message,
      ),
  ];

  final finder = _BodyFinder(target: bodySpan);
  unit.accept(finder);
  final body = finder.result;

  if (body == null) {
    if (bodySpan != null) {
      throw ParseException(
        'No function body found at offset ${bodySpan.offset}.',
      );
    }
    throw const ParseException('No function body found in source.');
  }

  if (body is! BlockFunctionBody) {
    throw ParseException(
      'Function body at offset ${body.offset} is not a block body '
      '(arrow or empty body). M8.0a only models block bodies.',
    );
  }

  return FunctionBodyModel(
    body: _convertBlock(body.block, source),
    diagnostics: diagnostics,
  );
}

/// Converts an analyzer `Block` to a `StatementBlock`. Shared between
/// function bodies and nested then/else blocks of `IfStatementNode`.
StatementBlock _convertBlock(Block block, String source) {
  final outerSpan = SourceSpan(offset: block.offset, length: block.length);
  final innerStart = block.leftBracket.offset + block.leftBracket.length;
  final innerLength = block.rightBracket.offset - innerStart;
  final innerSpan = SourceSpan(offset: innerStart, length: innerLength);

  final statements = <StatementNode>[];
  for (final stmt in block.statements) {
    statements.add(_convertStatement(stmt, source));
  }

  return StatementBlock(
    blockSpan: outerSpan,
    innerSpan: innerSpan,
    statements: statements,
  );
}

StatementNode _convertStatement(Statement stmt, String source) {
  final span = SourceSpan(offset: stmt.offset, length: stmt.length);
  if (stmt is VariableDeclarationStatement) {
    return _convertVariableDeclarationStatement(stmt, source);
  }
  if (stmt is ExpressionStatement) {
    final expr = stmt.expression;
    if (expr is ThrowExpression) {
      final thrown = expr.expression;
      return ThrowStatementNode(
        throwKeywordSpan: SourceSpan(
          offset: expr.throwKeyword.offset,
          length: expr.throwKeyword.length,
        ),
        expressionSource: source.substring(
          thrown.offset,
          thrown.offset + thrown.length,
        ),
        expressionSpan:
            SourceSpan(offset: thrown.offset, length: thrown.length),
        sourceSpan: span,
      );
    }
    final exprSpan = SourceSpan(offset: expr.offset, length: expr.length);
    return ExpressionStatementNode(
      expressionSource: source.substring(
        expr.offset,
        expr.offset + expr.length,
      ),
      expressionSpan: exprSpan,
      sourceSpan: span,
    );
  }
  if (stmt is ReturnStatement) {
    final expr = stmt.expression;
    if (expr == null) {
      return ReturnStatementNode(
        expressionSource: null,
        expressionSpan: null,
        sourceSpan: span,
      );
    }
    return ReturnStatementNode(
      expressionSource: source.substring(
        expr.offset,
        expr.offset + expr.length,
      ),
      expressionSpan: SourceSpan(offset: expr.offset, length: expr.length),
      sourceSpan: span,
    );
  }
  if (stmt is IfStatement) {
    final asIf = _tryConvertIfStatement(stmt, source, span);
    if (asIf != null) return asIf;
    // Fall through to opaque if the if-statement shape isn't supported
    // (bare-statement body, etc.).
  }
  if (stmt is ForStatement) {
    final asFor = _tryConvertForStatement(stmt, source, span);
    if (asFor != null) return asFor;
  }
  if (stmt is WhileStatement) {
    final asWhile = _tryConvertWhileStatement(stmt, source, span);
    if (asWhile != null) return asWhile;
  }
  if (stmt is DoStatement) {
    final asDo = _tryConvertDoStatement(stmt, source, span);
    if (asDo != null) return asDo;
  }
  if (stmt is TryStatement) {
    final asTry = _tryConvertTryStatement(stmt, source, span);
    if (asTry != null) return asTry;
  }
  if (stmt is SwitchStatement) {
    final asSwitch = _tryConvertSwitchStatement(stmt, source, span);
    if (asSwitch != null) return asSwitch;
  }
  // Anything else (yield/break/continue/labeled stmts/...) or an
  // unsupported control-flow shape — preserve verbatim.
  return OpaqueStatementNode(
    sourceText: source.substring(stmt.offset, stmt.offset + stmt.length),
    sourceSpan: span,
  );
}

/// Attempts to convert an `IfStatement` into an `IfStatementNode`.
/// Returns null when the shape isn't supported: a non-block then
/// statement, or an else clause that's neither null nor a block nor a
/// recursively-supported nested `if`. Callers fall through to
/// `OpaqueStatementNode` for the unsupported cases.
///
/// **Else-if (M8.0c):** an else clause that's another `IfStatement`
/// recurses into this same function. If the nested if is itself
/// supported, the outer node carries it as `elseIf`. If the nested if
/// is unsupported (e.g. bare-body deep in the chain), the WHOLE chain
/// becomes opaque — returning null here makes the caller emit one
/// opaque statement covering the entire outer if.
IfStatementNode? _tryConvertIfStatement(
  IfStatement stmt,
  String source,
  SourceSpan span,
) {
  final thenStmt = stmt.thenStatement;
  if (thenStmt is! Block) {
    return null;
  }
  final elseStmt = stmt.elseStatement;
  // Allowed: no else, else-block, or else-if (recursively supported).
  // Reject `else <bareStatement>;`.
  IfStatementNode? elseIf;
  StatementBlock? elseBlock;
  if (elseStmt is Block) {
    elseBlock = _convertBlock(elseStmt, source);
  } else if (elseStmt is IfStatement) {
    final nestedSpan =
        SourceSpan(offset: elseStmt.offset, length: elseStmt.length);
    elseIf = _tryConvertIfStatement(elseStmt, source, nestedSpan);
    if (elseIf == null) {
      // The nested else-if is itself unsupported (e.g. bare-body branch).
      // Reject the entire chain so the caller falls through to opaque.
      return null;
    }
  } else if (elseStmt != null) {
    return null;
  }

  final condition = stmt.expression;
  final conditionSpan =
      SourceSpan(offset: condition.offset, length: condition.length);
  final conditionSource = source.substring(
    condition.offset,
    condition.offset + condition.length,
  );

  return IfStatementNode(
    ifKeywordSpan: SourceSpan(
      offset: stmt.ifKeyword.offset,
      length: stmt.ifKeyword.length,
    ),
    conditionSource: conditionSource,
    conditionSpan: conditionSpan,
    thenBlock: _convertBlock(thenStmt, source),
    elseKeywordSpan: stmt.elseKeyword == null
        ? null
        : SourceSpan(
            offset: stmt.elseKeyword!.offset,
            length: stmt.elseKeyword!.length,
          ),
    elseBlock: elseBlock,
    elseIf: elseIf,
    sourceSpan: span,
  );
}

/// Attempts to convert a `ForStatement` into a `ForStatementNode`.
/// Returns null when the body isn't a `Block`. The header
/// (`(...)` between `for` / optional `await` and the body) is captured
/// as raw source — its internal structure (c-style triple vs for-each
/// vs pattern-for) is not yet modeled.
ForStatementNode? _tryConvertForStatement(
  ForStatement stmt,
  String source,
  SourceSpan span,
) {
  final body = stmt.body;
  if (body is! Block) return null;

  final lp = stmt.leftParenthesis;
  final rp = stmt.rightParenthesis;
  final headerOffset = lp.offset;
  final headerLength = (rp.offset + rp.length) - lp.offset;
  final headerSpan = SourceSpan(offset: headerOffset, length: headerLength);
  final headerSource = source.substring(
    headerOffset,
    headerOffset + headerLength,
  );

  return ForStatementNode(
    forKeywordSpan: SourceSpan(
      offset: stmt.forKeyword.offset,
      length: stmt.forKeyword.length,
    ),
    awaitKeywordSpan: stmt.awaitKeyword == null
        ? null
        : SourceSpan(
            offset: stmt.awaitKeyword!.offset,
            length: stmt.awaitKeyword!.length,
          ),
    headerSource: headerSource,
    headerSpan: headerSpan,
    body: _convertBlock(body, source),
    sourceSpan: span,
  );
}

/// Attempts to convert a `DoStatement` into a `DoStatementNode`.
/// Returns null when the body isn't a `Block`.
DoStatementNode? _tryConvertDoStatement(
  DoStatement stmt,
  String source,
  SourceSpan span,
) {
  final body = stmt.body;
  if (body is! Block) return null;

  final condition = stmt.condition;
  final conditionSpan =
      SourceSpan(offset: condition.offset, length: condition.length);
  final conditionSource = source.substring(
    condition.offset,
    condition.offset + condition.length,
  );

  return DoStatementNode(
    doKeywordSpan: SourceSpan(
      offset: stmt.doKeyword.offset,
      length: stmt.doKeyword.length,
    ),
    body: _convertBlock(body, source),
    whileKeywordSpan: SourceSpan(
      offset: stmt.whileKeyword.offset,
      length: stmt.whileKeyword.length,
    ),
    conditionSource: conditionSource,
    conditionSpan: conditionSpan,
    sourceSpan: span,
  );
}

/// Attempts to convert a `TryStatement` into a `TryStatementNode`.
/// Returns null when the try body, any catch body, or the finally body
/// isn't a `Block` (the grammar guarantees blocks today, but the check
/// is defensive so any future shape extension falls through to opaque).
TryStatementNode? _tryConvertTryStatement(
  TryStatement stmt,
  String source,
  SourceSpan span,
) {
  final tryBody = stmt.body;
  // (Per grammar, `tryBody` is always a Block — but check defensively
  // in case the grammar evolves.)
  // ignore: unnecessary_type_check
  if (tryBody is! Block) return null;

  final catchClauses = <CatchClauseNode>[];
  for (final clause in stmt.catchClauses) {
    final converted = _convertCatchClause(clause, source);
    if (converted == null) return null;
    catchClauses.add(converted);
  }

  final finallyBlock = stmt.finallyBlock;
  StatementBlock? convertedFinally;
  if (finallyBlock != null) {
    convertedFinally = _convertBlock(finallyBlock, source);
  }

  return TryStatementNode(
    tryKeywordSpan: SourceSpan(
      offset: stmt.tryKeyword.offset,
      length: stmt.tryKeyword.length,
    ),
    tryBlock: _convertBlock(tryBody, source),
    catchClauses: catchClauses,
    finallyKeywordSpan: stmt.finallyKeyword == null
        ? null
        : SourceSpan(
            offset: stmt.finallyKeyword!.offset,
            length: stmt.finallyKeyword!.length,
          ),
    finallyBlock: convertedFinally,
    sourceSpan: span,
  );
}

CatchClauseNode? _convertCatchClause(CatchClause clause, String source) {
  final body = clause.body;
  // ignore: unnecessary_type_check
  if (body is! Block) return null;

  final exceptionType = clause.exceptionType;
  final exceptionParameter = clause.exceptionParameter;
  final stackTraceParameter = clause.stackTraceParameter;

  return CatchClauseNode(
    onKeywordSpan: clause.onKeyword == null
        ? null
        : SourceSpan(
            offset: clause.onKeyword!.offset,
            length: clause.onKeyword!.length,
          ),
    exceptionTypeSource: exceptionType == null
        ? null
        : source.substring(
            exceptionType.offset,
            exceptionType.offset + exceptionType.length,
          ),
    exceptionTypeSpan: exceptionType == null
        ? null
        : SourceSpan(
            offset: exceptionType.offset,
            length: exceptionType.length,
          ),
    catchKeywordSpan: clause.catchKeyword == null
        ? null
        : SourceSpan(
            offset: clause.catchKeyword!.offset,
            length: clause.catchKeyword!.length,
          ),
    exceptionParameterName: exceptionParameter?.name.lexeme,
    exceptionParameterSpan: exceptionParameter == null
        ? null
        : SourceSpan(
            offset: exceptionParameter.name.offset,
            length: exceptionParameter.name.length,
          ),
    stackTraceParameterName: stackTraceParameter?.name.lexeme,
    stackTraceParameterSpan: stackTraceParameter == null
        ? null
        : SourceSpan(
            offset: stackTraceParameter.name.offset,
            length: stackTraceParameter.name.length,
          ),
    body: _convertBlock(body, source),
    sourceSpan: SourceSpan(offset: clause.offset, length: clause.length),
  );
}

/// Attempts to convert a `SwitchStatement` into a `SwitchStatementNode`.
/// Each member (case / default) becomes a `SwitchMemberNode` with a
/// brace-less `StatementBlock` body. The pattern of a case is captured
/// as opaque source (whether it's a Dart 2 constant expression or a
/// Dart 3 pattern); same for the optional `when` guard.
SwitchStatementNode? _tryConvertSwitchStatement(
  SwitchStatement stmt,
  String source,
  SourceSpan span,
) {
  final expression = stmt.expression;
  final expressionSpan =
      SourceSpan(offset: expression.offset, length: expression.length);
  final expressionSource = source.substring(
    expression.offset,
    expression.offset + expression.length,
  );

  final members = <SwitchMemberNode>[];
  final memberList = stmt.members;
  final rightBracketOffset = stmt.rightBracket.offset;
  for (var i = 0; i < memberList.length; i++) {
    final member = memberList[i];
    // Body span: from just after this member's `:` colon, up to either
    // the next member's start (its first label or keyword) or the
    // switch's closing `}`.
    final bodyStart = member.colon.offset + member.colon.length;
    final bodyEnd = i + 1 < memberList.length
        ? memberList[i + 1].offset
        : rightBracketOffset;
    final bodyLength = bodyEnd - bodyStart;
    final bodySpan = SourceSpan(offset: bodyStart, length: bodyLength);

    final bodyStatements = <StatementNode>[
      for (final s in member.statements) _convertStatement(s, source),
    ];
    final body = StatementBlock(
      blockSpan: bodySpan,
      innerSpan: bodySpan,
      statements: bodyStatements,
      hasBraces: false,
    );

    final memberSpan = SourceSpan(offset: member.offset, length: member.length);

    if (member is SwitchCase) {
      final caseExpression = member.expression;
      final patternSpan = SourceSpan(
        offset: caseExpression.offset,
        length: caseExpression.length,
      );
      // Legacy `case constantExpr:` IS a constant pattern semantically.
      // Wrap it as `ConstantPatternNode` for consistency with Dart 3
      // cases that use `case <ConstantPattern>:`.
      members.add(SwitchCaseNode(
        keywordSpan: SourceSpan(
          offset: member.keyword.offset,
          length: member.keyword.length,
        ),
        patternSource: source.substring(
          caseExpression.offset,
          caseExpression.offset + caseExpression.length,
        ),
        patternSpan: patternSpan,
        pattern: ConstantPatternNode(
          constKeywordSpan: null,
          expressionSource: source.substring(
            caseExpression.offset,
            caseExpression.offset + caseExpression.length,
          ),
          expressionSpan: patternSpan,
          sourceSpan: patternSpan,
        ),
        whenKeywordSpan: null,
        whenGuardSource: null,
        whenGuardSpan: null,
        colonSpan: SourceSpan(
          offset: member.colon.offset,
          length: member.colon.length,
        ),
        body: body,
        sourceSpan: memberSpan,
      ));
    } else if (member is SwitchPatternCase) {
      final guarded = member.guardedPattern;
      final pattern = guarded.pattern;
      final whenClause = guarded.whenClause;
      members.add(SwitchCaseNode(
        keywordSpan: SourceSpan(
          offset: member.keyword.offset,
          length: member.keyword.length,
        ),
        patternSource: source.substring(
          pattern.offset,
          pattern.offset + pattern.length,
        ),
        patternSpan: SourceSpan(
          offset: pattern.offset,
          length: pattern.length,
        ),
        pattern: _convertPattern(pattern, source),
        whenKeywordSpan: whenClause == null
            ? null
            : SourceSpan(
                offset: whenClause.whenKeyword.offset,
                length: whenClause.whenKeyword.length,
              ),
        whenGuardSource: whenClause == null
            ? null
            : source.substring(
                whenClause.expression.offset,
                whenClause.expression.offset + whenClause.expression.length,
              ),
        whenGuardSpan: whenClause == null
            ? null
            : SourceSpan(
                offset: whenClause.expression.offset,
                length: whenClause.expression.length,
              ),
        colonSpan: SourceSpan(
          offset: member.colon.offset,
          length: member.colon.length,
        ),
        body: body,
        sourceSpan: memberSpan,
      ));
    } else if (member is SwitchDefault) {
      members.add(SwitchDefaultNode(
        keywordSpan: SourceSpan(
          offset: member.keyword.offset,
          length: member.keyword.length,
        ),
        colonSpan: SourceSpan(
          offset: member.colon.offset,
          length: member.colon.length,
        ),
        body: body,
        sourceSpan: memberSpan,
      ));
    } else {
      // Unknown member kind — reject the whole switch to opaque.
      return null;
    }
  }

  return SwitchStatementNode(
    switchKeywordSpan: SourceSpan(
      offset: stmt.switchKeyword.offset,
      length: stmt.switchKeyword.length,
    ),
    expressionSource: expressionSource,
    expressionSpan: expressionSpan,
    leftBracketSpan: SourceSpan(
      offset: stmt.leftBracket.offset,
      length: stmt.leftBracket.length,
    ),
    members: members,
    rightBracketSpan: SourceSpan(
      offset: stmt.rightBracket.offset,
      length: stmt.rightBracket.length,
    ),
    sourceSpan: span,
  );
}

/// Attempts to convert a `WhileStatement` into a `WhileStatementNode`.
/// Returns null when the body isn't a `Block`.
WhileStatementNode? _tryConvertWhileStatement(
  WhileStatement stmt,
  String source,
  SourceSpan span,
) {
  final body = stmt.body;
  if (body is! Block) return null;

  final condition = stmt.condition;
  final conditionSpan =
      SourceSpan(offset: condition.offset, length: condition.length);
  final conditionSource = source.substring(
    condition.offset,
    condition.offset + condition.length,
  );

  return WhileStatementNode(
    whileKeywordSpan: SourceSpan(
      offset: stmt.whileKeyword.offset,
      length: stmt.whileKeyword.length,
    ),
    conditionSource: conditionSource,
    conditionSpan: conditionSpan,
    body: _convertBlock(body, source),
    sourceSpan: span,
  );
}

VariableDeclarationStatementNode _convertVariableDeclarationStatement(
  VariableDeclarationStatement stmt,
  String source,
) {
  final list = stmt.variables;
  final typeNode = list.type;
  final keyword = list.keyword;
  final isFinal = keyword != null && keyword.keyword == Keyword.FINAL;
  final isVar = keyword != null && keyword.keyword == Keyword.VAR;
  final isConst = keyword != null && keyword.keyword == Keyword.CONST;
  final isLate = list.lateKeyword != null;

  final variables = <DeclaredVariable>[
    for (final v in list.variables)
      DeclaredVariable(
        name: v.name.lexeme,
        nameSpan: SourceSpan(offset: v.name.offset, length: v.name.length),
        initializerSource: v.initializer == null
            ? null
            : source.substring(
                v.initializer!.offset,
                v.initializer!.offset + v.initializer!.length,
              ),
        initializerSpan: v.initializer == null
            ? null
            : SourceSpan(
                offset: v.initializer!.offset,
                length: v.initializer!.length,
              ),
      ),
  ];

  return VariableDeclarationStatementNode(
    typeName: typeNode?.toSource(),
    typeSpan: typeNode == null
        ? null
        : SourceSpan(offset: typeNode.offset, length: typeNode.length),
    isFinal: isFinal,
    isVar: isVar,
    isLate: isLate,
    isConst: isConst,
    variables: variables,
    sourceSpan: SourceSpan(offset: stmt.offset, length: stmt.length),
  );
}

/// Converts an analyzer `DartPattern` into the corresponding
/// `PatternNode`. Total: returns `OpaquePatternNode` for pattern kinds
/// the M8.0f slice doesn't model structurally (object, record, list,
/// map, logical-and, relational, null-check, null-assert, cast,
/// parenthesized).
PatternNode _convertPattern(DartPattern pattern, String source) {
  final span = SourceSpan(offset: pattern.offset, length: pattern.length);

  if (pattern is ConstantPattern) {
    final expr = pattern.expression;
    return ConstantPatternNode(
      constKeywordSpan: pattern.constKeyword == null
          ? null
          : SourceSpan(
              offset: pattern.constKeyword!.offset,
              length: pattern.constKeyword!.length,
            ),
      expressionSource: source.substring(
        expr.offset,
        expr.offset + expr.length,
      ),
      expressionSpan: SourceSpan(offset: expr.offset, length: expr.length),
      sourceSpan: span,
    );
  }

  if (pattern is DeclaredVariablePattern) {
    final type = pattern.type;
    return DeclaredVariablePatternNode(
      keywordSpan: pattern.keyword == null
          ? null
          : SourceSpan(
              offset: pattern.keyword!.offset,
              length: pattern.keyword!.length,
            ),
      typeSource: type == null
          ? null
          : source.substring(type.offset, type.offset + type.length),
      typeSpan: type == null
          ? null
          : SourceSpan(offset: type.offset, length: type.length),
      name: pattern.name.lexeme,
      nameSpan: SourceSpan(
        offset: pattern.name.offset,
        length: pattern.name.length,
      ),
      sourceSpan: span,
    );
  }

  if (pattern is WildcardPattern) {
    final type = pattern.type;
    return WildcardPatternNode(
      keywordSpan: pattern.keyword == null
          ? null
          : SourceSpan(
              offset: pattern.keyword!.offset,
              length: pattern.keyword!.length,
            ),
      typeSource: type == null
          ? null
          : source.substring(type.offset, type.offset + type.length),
      typeSpan: type == null
          ? null
          : SourceSpan(offset: type.offset, length: type.length),
      underscoreSpan: SourceSpan(
        offset: pattern.name.offset,
        length: pattern.name.length,
      ),
      sourceSpan: span,
    );
  }

  if (pattern is LogicalOrPattern) {
    final operands = <PatternNode>[];
    final operatorSpans = <SourceSpan>[];
    _flattenLogicalOr(pattern, source, operands, operatorSpans);
    return LogicalOrPatternNode(
      operands: operands,
      operatorSpans: operatorSpans,
      sourceSpan: span,
    );
  }

  if (pattern is ObjectPattern) {
    return ObjectPatternNode(
      typeNameSource: source.substring(
        pattern.type.offset,
        pattern.type.offset + pattern.type.length,
      ),
      typeNameSpan: SourceSpan(
        offset: pattern.type.offset,
        length: pattern.type.length,
      ),
      leftParenSpan: SourceSpan(
        offset: pattern.leftParenthesis.offset,
        length: pattern.leftParenthesis.length,
      ),
      fields: [
        for (final f in pattern.fields) _convertPatternField(f, source),
      ],
      rightParenSpan: SourceSpan(
        offset: pattern.rightParenthesis.offset,
        length: pattern.rightParenthesis.length,
      ),
      sourceSpan: span,
    );
  }

  if (pattern is RecordPattern) {
    return RecordPatternNode(
      leftParenSpan: SourceSpan(
        offset: pattern.leftParenthesis.offset,
        length: pattern.leftParenthesis.length,
      ),
      fields: [
        for (final f in pattern.fields) _convertPatternField(f, source),
      ],
      rightParenSpan: SourceSpan(
        offset: pattern.rightParenthesis.offset,
        length: pattern.rightParenthesis.length,
      ),
      sourceSpan: span,
    );
  }

  // List / map / logical-and / relational / null-check / null-assert /
  // cast / parenthesized — all opaque for M8.0g. Future milestones can
  // promote individual kinds as concrete edits demand.
  return OpaquePatternNode(
    sourceText:
        source.substring(pattern.offset, pattern.offset + pattern.length),
    sourceSpan: span,
  );
}

/// Converts an analyzer `PatternField` into a kernel `PatternField`.
/// Handles three field shapes:
///   * `Foo(1, 2)` — positional (no name node).
///   * `Foo(x: 1)` — explicit named (name node with explicit token).
///   * `Foo(:var x)` — shorthand named (name node with null name token;
///     field name is implied by the inner pattern's variable).
PatternField _convertPatternField(
  ast.PatternField field,
  String source,
) {
  final nameNode = field.name;
  final subPattern = _convertPattern(field.pattern, source);
  final fieldSpan = SourceSpan(offset: field.offset, length: field.length);

  if (nameNode == null) {
    return PatternField(
      fieldName: null,
      fieldNameSpan: null,
      colonSpan: null,
      isShorthand: false,
      pattern: subPattern,
      sourceSpan: fieldSpan,
    );
  }

  final colonSpan = SourceSpan(
    offset: nameNode.colon.offset,
    length: nameNode.colon.length,
  );
  final nameToken = nameNode.name;
  if (nameToken == null) {
    return PatternField(
      fieldName: null,
      fieldNameSpan: null,
      colonSpan: colonSpan,
      isShorthand: true,
      pattern: subPattern,
      sourceSpan: fieldSpan,
    );
  }

  return PatternField(
    fieldName: nameToken.lexeme,
    fieldNameSpan:
        SourceSpan(offset: nameToken.offset, length: nameToken.length),
    colonSpan: colonSpan,
    isShorthand: false,
    pattern: subPattern,
    sourceSpan: fieldSpan,
  );
}

/// Recursively flattens a left-associative binary `LogicalOrPattern`
/// tree into a flat operand list. `1 || 2 || 3` is parsed as
/// `(1 || 2) || 3` — this helper unfolds it into `[1, 2, 3]` plus the
/// two `||` token spans.
void _flattenLogicalOr(
  LogicalOrPattern node,
  String source,
  List<PatternNode> operands,
  List<SourceSpan> operatorSpans,
) {
  final left = node.leftOperand;
  if (left is LogicalOrPattern) {
    _flattenLogicalOr(left, source, operands, operatorSpans);
  } else {
    operands.add(_convertPattern(left, source));
  }
  operatorSpans.add(SourceSpan(
    offset: node.operator.offset,
    length: node.operator.length,
  ));
  final right = node.rightOperand;
  if (right is LogicalOrPattern) {
    _flattenLogicalOr(right, source, operands, operatorSpans);
  } else {
    operands.add(_convertPattern(right, source));
  }
}

/// AST visitor that locates the first (or matching) block function body
/// in a compilation unit. Pre-order traversal — a class's first method
/// body comes back before that method's nested closures.
class _BodyFinder extends RecursiveAstVisitor<void> {
  _BodyFinder({this.target});

  /// When non-null, returns ONLY the body whose offset matches `target.offset`.
  /// When null, returns the first `BlockFunctionBody` encountered.
  final SourceSpan? target;
  FunctionBody? result;

  @override
  void visitBlockFunctionBody(BlockFunctionBody node) {
    if (result != null) return;
    if (target == null || node.offset == target!.offset) {
      result = node;
      return;
    }
    super.visitBlockFunctionBody(node);
  }

  @override
  void visitExpressionFunctionBody(ExpressionFunctionBody node) {
    if (result != null) return;
    if (target != null && node.offset == target!.offset) {
      result = node;
      return;
    }
    super.visitExpressionFunctionBody(node);
  }

  @override
  void visitEmptyFunctionBody(EmptyFunctionBody node) {
    if (result != null) return;
    if (target != null && node.offset == target!.offset) {
      result = node;
    }
  }
}
