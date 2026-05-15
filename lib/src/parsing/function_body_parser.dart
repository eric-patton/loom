import 'package:analyzer/dart/analysis/utilities.dart';
// Hide analyzer types that clash with the kernel's domain names.
// We still need the analyzer types via prefixed aliases.
import 'package:analyzer/dart/ast/ast.dart'
    hide ClassMember, PatternField, ListPatternElement, MapPatternElement;
import 'package:analyzer/dart/ast/ast.dart' as ast
    show PatternField, ListPatternElement, MapPatternElement;
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
        thrownExpression: _convertExpression(thrown, source),
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
      expression: _convertExpression(expr, source),
      switchExpression: expr is SwitchExpression
          ? _convertSwitchExpression(expr, source)
          : null,
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
      returnedExpression: _convertExpression(expr, source),
      switchExpression: expr is SwitchExpression
          ? _convertSwitchExpression(expr, source)
          : null,
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
  if (stmt is YieldStatement) {
    final expr = stmt.expression;
    return YieldStatementNode(
      yieldKeywordSpan: SourceSpan(
        offset: stmt.yieldKeyword.offset,
        length: stmt.yieldKeyword.length,
      ),
      starSpan: stmt.star == null
          ? null
          : SourceSpan(
              offset: stmt.star!.offset,
              length: stmt.star!.length,
            ),
      expressionSource: source.substring(
        expr.offset,
        expr.offset + expr.length,
      ),
      expressionSpan: SourceSpan(offset: expr.offset, length: expr.length),
      sourceSpan: span,
      yieldedExpression: _convertExpression(expr, source),
    );
  }
  if (stmt is BreakStatement) {
    final label = stmt.label;
    return BreakStatementNode(
      breakKeywordSpan: SourceSpan(
        offset: stmt.breakKeyword.offset,
        length: stmt.breakKeyword.length,
      ),
      labelName: label?.name.lexeme,
      labelSpan: label == null
          ? null
          : SourceSpan(
              offset: label.name.offset,
              length: label.name.length,
            ),
      sourceSpan: span,
    );
  }
  if (stmt is ContinueStatement) {
    final label = stmt.label;
    return ContinueStatementNode(
      continueKeywordSpan: SourceSpan(
        offset: stmt.continueKeyword.offset,
        length: stmt.continueKeyword.length,
      ),
      labelName: label?.name.lexeme,
      labelSpan: label == null
          ? null
          : SourceSpan(
              offset: label.name.offset,
              length: label.name.length,
            ),
      sourceSpan: span,
    );
  }
  if (stmt is LabeledStatement) {
    return LabeledStatementNode(
      labels: [
        for (final l in stmt.labels)
          LabelNode(
            name: l.name.lexeme,
            nameSpan: SourceSpan(
              offset: l.name.offset,
              length: l.name.length,
            ),
            colonSpan: SourceSpan(
              offset: l.colon.offset,
              length: l.colon.length,
            ),
            sourceSpan: SourceSpan(offset: l.offset, length: l.length),
          ),
      ],
      statement: _convertStatement(stmt.statement, source),
      sourceSpan: span,
    );
  }
  // Anything else (rare or future statement shapes) — preserve verbatim.
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
    condition: _convertExpression(condition, source),
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
/// Returns null when the body isn't a `Block`. The header is
/// captured BOTH as raw source AND as a structured `ForLoopHeader`
/// (M8.2): `CStyleForHeader`, `ForEachHeader`, or
/// `OpaqueForLoopHeader` (pattern-for variants).
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
    header: _convertForLoopHeader(stmt, source, headerSource, headerSpan),
    body: _convertBlock(body, source),
    sourceSpan: span,
  );
}

/// Converts a `ForStatement`'s parts into a structured `ForLoopHeader`.
/// Returns `OpaqueForLoopHeader` for pattern-for variants
/// (`ForPartsWithPattern`, `ForEachPartsWithPattern`) — those are
/// less common and modeling pattern-for binding requires the M8.0f
/// pattern infrastructure to apply to declarations, not just switch
/// cases. Deferred.
ForLoopHeader _convertForLoopHeader(
  ForStatement stmt,
  String source,
  String headerSource,
  SourceSpan headerSpan,
) {
  final parts = stmt.forLoopParts;

  if (parts is ForPartsWithDeclarations) {
    return _convertCStyleHeader(
      initSource: source.substring(
        parts.variables.offset,
        parts.variables.offset + parts.variables.length,
      ),
      initSpan: SourceSpan(
        offset: parts.variables.offset,
        length: parts.variables.length,
      ),
      parts: parts,
      source: source,
      headerSpan: headerSpan,
    );
  }
  if (parts is ForPartsWithExpression) {
    final init = parts.initialization;
    return _convertCStyleHeader(
      initSource: init == null
          ? null
          : source.substring(init.offset, init.offset + init.length),
      initSpan: init == null
          ? null
          : SourceSpan(offset: init.offset, length: init.length),
      parts: parts,
      source: source,
      headerSpan: headerSpan,
    );
  }
  if (parts is ForEachPartsWithDeclaration) {
    final lv = parts.loopVariable;
    return ForEachHeader(
      keywordSpan: lv.keyword == null
          ? null
          : SourceSpan(
              offset: lv.keyword!.offset,
              length: lv.keyword!.length,
            ),
      typeSource: lv.type == null
          ? null
          : source.substring(
              lv.type!.offset,
              lv.type!.offset + lv.type!.length,
            ),
      typeSpan: lv.type == null
          ? null
          : SourceSpan(offset: lv.type!.offset, length: lv.type!.length),
      loopVariableName: lv.name.lexeme,
      loopVariableSpan:
          SourceSpan(offset: lv.name.offset, length: lv.name.length),
      isExistingIdentifier: false,
      inKeywordSpan: SourceSpan(
        offset: parts.inKeyword.offset,
        length: parts.inKeyword.length,
      ),
      iterableSource: source.substring(
        parts.iterable.offset,
        parts.iterable.offset + parts.iterable.length,
      ),
      iterableSpan: SourceSpan(
        offset: parts.iterable.offset,
        length: parts.iterable.length,
      ),
      sourceSpan: headerSpan,
    );
  }
  if (parts is ForEachPartsWithIdentifier) {
    final id = parts.identifier;
    return ForEachHeader(
      keywordSpan: null,
      typeSource: null,
      typeSpan: null,
      loopVariableName: id.name,
      loopVariableSpan: SourceSpan(offset: id.offset, length: id.length),
      isExistingIdentifier: true,
      inKeywordSpan: SourceSpan(
        offset: parts.inKeyword.offset,
        length: parts.inKeyword.length,
      ),
      iterableSource: source.substring(
        parts.iterable.offset,
        parts.iterable.offset + parts.iterable.length,
      ),
      iterableSpan: SourceSpan(
        offset: parts.iterable.offset,
        length: parts.iterable.length,
      ),
      sourceSpan: headerSpan,
    );
  }
  // ForPartsWithPattern, ForEachPartsWithPattern, or any future shape.
  return OpaqueForLoopHeader(
    headerSource: headerSource,
    sourceSpan: headerSpan,
  );
}

CStyleForHeader _convertCStyleHeader({
  required String? initSource,
  required SourceSpan? initSpan,
  required ForParts parts,
  required String source,
  required SourceSpan headerSpan,
}) {
  final condition = parts.condition;
  final updaterSources = <String>[];
  final updaterSpans = <SourceSpan>[];
  for (final u in parts.updaters) {
    updaterSources.add(source.substring(u.offset, u.offset + u.length));
    updaterSpans.add(SourceSpan(offset: u.offset, length: u.length));
  }
  return CStyleForHeader(
    initSource: initSource,
    initSpan: initSpan,
    leftSeparatorSpan: SourceSpan(
      offset: parts.leftSeparator.offset,
      length: parts.leftSeparator.length,
    ),
    conditionSource: condition == null
        ? null
        : source.substring(
            condition.offset,
            condition.offset + condition.length,
          ),
    conditionSpan: condition == null
        ? null
        : SourceSpan(offset: condition.offset, length: condition.length),
    rightSeparatorSpan: SourceSpan(
      offset: parts.rightSeparator.offset,
      length: parts.rightSeparator.length,
    ),
    updaterSources: updaterSources,
    updaterSpans: updaterSpans,
    sourceSpan: headerSpan,
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
    condition: _convertExpression(condition, source),
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
    condition: _convertExpression(condition, source),
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
        initializerExpression: v.initializer == null
            ? null
            : _convertExpression(v.initializer!, source),
        initializerSwitchExpression: v.initializer is SwitchExpression
            ? _convertSwitchExpression(
                v.initializer! as SwitchExpression, source)
            : null,
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

  if (pattern is ListPattern) {
    final typeArgs = pattern.typeArguments;
    return ListPatternNode(
      typeArgumentsSource: typeArgs == null
          ? null
          : source.substring(
              typeArgs.offset,
              typeArgs.offset + typeArgs.length,
            ),
      typeArgumentsSpan: typeArgs == null
          ? null
          : SourceSpan(offset: typeArgs.offset, length: typeArgs.length),
      leftBracketSpan: SourceSpan(
        offset: pattern.leftBracket.offset,
        length: pattern.leftBracket.length,
      ),
      elements: [
        for (final e in pattern.elements) _convertListPatternElement(e, source),
      ],
      rightBracketSpan: SourceSpan(
        offset: pattern.rightBracket.offset,
        length: pattern.rightBracket.length,
      ),
      sourceSpan: span,
    );
  }

  if (pattern is MapPattern) {
    final typeArgs = pattern.typeArguments;
    return MapPatternNode(
      typeArgumentsSource: typeArgs == null
          ? null
          : source.substring(
              typeArgs.offset,
              typeArgs.offset + typeArgs.length,
            ),
      typeArgumentsSpan: typeArgs == null
          ? null
          : SourceSpan(offset: typeArgs.offset, length: typeArgs.length),
      leftBracketSpan: SourceSpan(
        offset: pattern.leftBracket.offset,
        length: pattern.leftBracket.length,
      ),
      elements: [
        for (final e in pattern.elements) _convertMapPatternElement(e, source),
      ],
      rightBracketSpan: SourceSpan(
        offset: pattern.rightBracket.offset,
        length: pattern.rightBracket.length,
      ),
      sourceSpan: span,
    );
  }

  if (pattern is RelationalPattern) {
    return RelationalPatternNode(
      operator: pattern.operator.lexeme,
      operatorSpan: SourceSpan(
        offset: pattern.operator.offset,
        length: pattern.operator.length,
      ),
      operandSource: source.substring(
        pattern.operand.offset,
        pattern.operand.offset + pattern.operand.length,
      ),
      operandSpan: SourceSpan(
        offset: pattern.operand.offset,
        length: pattern.operand.length,
      ),
      sourceSpan: span,
    );
  }

  if (pattern is NullCheckPattern) {
    return NullCheckPatternNode(
      innerPattern: _convertPattern(pattern.pattern, source),
      operatorSpan: SourceSpan(
        offset: pattern.operator.offset,
        length: pattern.operator.length,
      ),
      sourceSpan: span,
    );
  }

  if (pattern is NullAssertPattern) {
    return NullAssertPatternNode(
      innerPattern: _convertPattern(pattern.pattern, source),
      operatorSpan: SourceSpan(
        offset: pattern.operator.offset,
        length: pattern.operator.length,
      ),
      sourceSpan: span,
    );
  }

  if (pattern is CastPattern) {
    return CastPatternNode(
      innerPattern: _convertPattern(pattern.pattern, source),
      asKeywordSpan: SourceSpan(
        offset: pattern.asToken.offset,
        length: pattern.asToken.length,
      ),
      typeSource: source.substring(
        pattern.type.offset,
        pattern.type.offset + pattern.type.length,
      ),
      typeSpan: SourceSpan(
        offset: pattern.type.offset,
        length: pattern.type.length,
      ),
      sourceSpan: span,
    );
  }

  if (pattern is ParenthesizedPattern) {
    return ParenthesizedPatternNode(
      leftParenSpan: SourceSpan(
        offset: pattern.leftParenthesis.offset,
        length: pattern.leftParenthesis.length,
      ),
      innerPattern: _convertPattern(pattern.pattern, source),
      rightParenSpan: SourceSpan(
        offset: pattern.rightParenthesis.offset,
        length: pattern.rightParenthesis.length,
      ),
      sourceSpan: span,
    );
  }

  if (pattern is LogicalAndPattern) {
    final operands = <PatternNode>[];
    final operatorSpans = <SourceSpan>[];
    _flattenLogicalAnd(pattern, source, operands, operatorSpans);
    return LogicalAndPatternNode(
      operands: operands,
      operatorSpans: operatorSpans,
      sourceSpan: span,
    );
  }

  // Safety fallback — every Dart 3 pattern kind known to analyzer 13
  // is handled above. This catches any new pattern shape introduced
  // by a future analyzer release.
  return OpaquePatternNode(
    sourceText:
        source.substring(pattern.offset, pattern.offset + pattern.length),
    sourceSpan: span,
  );
}

/// Recursively flattens a left-associative binary `LogicalAndPattern`
/// tree into a flat operand list. Same shape as `_flattenLogicalOr`.
void _flattenLogicalAnd(
  LogicalAndPattern node,
  String source,
  List<PatternNode> operands,
  List<SourceSpan> operatorSpans,
) {
  final left = node.leftOperand;
  if (left is LogicalAndPattern) {
    _flattenLogicalAnd(left, source, operands, operatorSpans);
  } else {
    operands.add(_convertPattern(left, source));
  }
  operatorSpans.add(SourceSpan(
    offset: node.operator.offset,
    length: node.operator.length,
  ));
  final right = node.rightOperand;
  if (right is LogicalAndPattern) {
    _flattenLogicalAnd(right, source, operands, operatorSpans);
  } else {
    operands.add(_convertPattern(right, source));
  }
}

ListPatternElement _convertListPatternElement(
  ast.ListPatternElement element,
  String source,
) {
  final span = SourceSpan(offset: element.offset, length: element.length);
  if (element is RestPatternElement) {
    return ListPatternRestElement(
      operatorSpan: SourceSpan(
        offset: element.operator.offset,
        length: element.operator.length,
      ),
      subPattern: element.pattern == null
          ? null
          : _convertPattern(element.pattern!, source),
      sourceSpan: span,
    );
  }
  if (element is DartPattern) {
    return ListPatternPatternElement(
      pattern: _convertPattern(element, source),
      sourceSpan: span,
    );
  }
  throw StateError('Unexpected list-pattern element type: '
      '${element.runtimeType}');
}

MapPatternElement _convertMapPatternElement(
  ast.MapPatternElement element,
  String source,
) {
  final span = SourceSpan(offset: element.offset, length: element.length);
  if (element is RestPatternElement) {
    return MapPatternRestElement(
      operatorSpan: SourceSpan(
        offset: element.operator.offset,
        length: element.operator.length,
      ),
      subPattern: element.pattern == null
          ? null
          : _convertPattern(element.pattern!, source),
      sourceSpan: span,
    );
  }
  if (element is MapPatternEntry) {
    return MapPatternEntryNode(
      keyExpressionSource: source.substring(
        element.key.offset,
        element.key.offset + element.key.length,
      ),
      keyExpressionSpan: SourceSpan(
        offset: element.key.offset,
        length: element.key.length,
      ),
      colonSpan: SourceSpan(
        offset: element.separator.offset,
        length: element.separator.length,
      ),
      pattern: _convertPattern(element.value, source),
      sourceSpan: span,
    );
  }
  throw StateError('Unexpected map-pattern element type: '
      '${element.runtimeType}');
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

/// Converts an analyzer `SwitchExpression` into a kernel
/// `SwitchExpressionNode`. Each case's guarded pattern is structured
/// via `_convertPattern`, and the result expression on the right of
/// `=>` is captured as opaque source (expression internals are not
/// modeled in M8.0h).
SwitchExpressionNode _convertSwitchExpression(
  SwitchExpression expr,
  String source,
) {
  final cases = <SwitchExpressionCaseNode>[];
  for (final c in expr.cases) {
    final guarded = c.guardedPattern;
    final pattern = guarded.pattern;
    final whenClause = guarded.whenClause;
    final result = c.expression;
    cases.add(SwitchExpressionCaseNode(
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
      arrowSpan: SourceSpan(offset: c.arrow.offset, length: c.arrow.length),
      resultExpressionSource: source.substring(
        result.offset,
        result.offset + result.length,
      ),
      resultExpressionSpan:
          SourceSpan(offset: result.offset, length: result.length),
      sourceSpan: SourceSpan(offset: c.offset, length: c.length),
    ));
  }
  return SwitchExpressionNode(
    switchKeywordSpan: SourceSpan(
      offset: expr.switchKeyword.offset,
      length: expr.switchKeyword.length,
    ),
    subjectSource: source.substring(
      expr.expression.offset,
      expr.expression.offset + expr.expression.length,
    ),
    subjectSpan: SourceSpan(
        offset: expr.expression.offset, length: expr.expression.length),
    leftBracketSpan: SourceSpan(
      offset: expr.leftBracket.offset,
      length: expr.leftBracket.length,
    ),
    cases: cases,
    rightBracketSpan: SourceSpan(
      offset: expr.rightBracket.offset,
      length: expr.rightBracket.length,
    ),
    sourceSpan: SourceSpan(offset: expr.offset, length: expr.length),
  );
}

/// Converts an analyzer `Expression` into a kernel `ExpressionNode`.
/// Total: returns `OpaqueExpressionNode` for kinds not modeled in
/// M8.2/M8.3.
ExpressionNode _convertExpression(Expression expr, String source) {
  final span = SourceSpan(offset: expr.offset, length: expr.length);
  final raw = source.substring(expr.offset, expr.offset + expr.length);

  if (expr is SimpleIdentifier) {
    return IdentifierExpressionNode(name: expr.name, sourceSpan: span);
  }

  if (expr is IntegerLiteral) {
    return LiteralExpressionNode(
      kind: LiteralKind.intLiteral,
      source: raw,
      sourceSpan: span,
    );
  }
  if (expr is DoubleLiteral) {
    return LiteralExpressionNode(
      kind: LiteralKind.doubleLiteral,
      source: raw,
      sourceSpan: span,
    );
  }
  if (expr is StringLiteral) {
    return LiteralExpressionNode(
      kind: LiteralKind.stringLiteral,
      source: raw,
      sourceSpan: span,
    );
  }
  if (expr is BooleanLiteral) {
    return LiteralExpressionNode(
      kind: LiteralKind.boolLiteral,
      source: raw,
      sourceSpan: span,
    );
  }
  if (expr is NullLiteral) {
    return LiteralExpressionNode(
      kind: LiteralKind.nullLiteral,
      source: raw,
      sourceSpan: span,
    );
  }

  if (expr is MethodInvocation) {
    final target = expr.target;
    final args = expr.argumentList;
    return MethodInvocationExpressionNode(
      target: target == null ? null : _convertExpression(target, source),
      dotSpan: expr.operator == null
          ? null
          : SourceSpan(
              offset: expr.operator!.offset,
              length: expr.operator!.length,
            ),
      methodName: expr.methodName.name,
      methodNameSpan: SourceSpan(
        offset: expr.methodName.offset,
        length: expr.methodName.length,
      ),
      argumentsSource: source.substring(
        args.offset,
        args.offset + args.length,
      ),
      argumentsSpan: SourceSpan(offset: args.offset, length: args.length),
      sourceSpan: span,
    );
  }

  if (expr is BinaryExpression) {
    return BinaryExpressionNode(
      leftOperand: _convertExpression(expr.leftOperand, source),
      operator: expr.operator.lexeme,
      operatorSpan: SourceSpan(
        offset: expr.operator.offset,
        length: expr.operator.length,
      ),
      rightOperand: _convertExpression(expr.rightOperand, source),
      sourceSpan: span,
    );
  }

  if (expr is AssignmentExpression) {
    return AssignmentExpressionNode(
      leftHandSide: _convertExpression(expr.leftHandSide, source),
      operator: expr.operator.lexeme,
      operatorSpan: SourceSpan(
        offset: expr.operator.offset,
        length: expr.operator.length,
      ),
      rightHandSide: _convertExpression(expr.rightHandSide, source),
      sourceSpan: span,
    );
  }

  if (expr is ConditionalExpression) {
    return ConditionalExpressionNode(
      condition: _convertExpression(expr.condition, source),
      questionSpan: SourceSpan(
        offset: expr.question.offset,
        length: expr.question.length,
      ),
      thenExpression: _convertExpression(expr.thenExpression, source),
      colonSpan: SourceSpan(
        offset: expr.colon.offset,
        length: expr.colon.length,
      ),
      elseExpression: _convertExpression(expr.elseExpression, source),
      sourceSpan: span,
    );
  }

  if (expr is AwaitExpression) {
    return AwaitExpressionNode(
      awaitKeywordSpan: SourceSpan(
        offset: expr.awaitKeyword.offset,
        length: expr.awaitKeyword.length,
      ),
      expression: _convertExpression(expr.expression, source),
      sourceSpan: span,
    );
  }

  if (expr is PrefixExpression) {
    return PrefixExpressionNode(
      operator: expr.operator.lexeme,
      operatorSpan: SourceSpan(
        offset: expr.operator.offset,
        length: expr.operator.length,
      ),
      operand: _convertExpression(expr.operand, source),
      sourceSpan: span,
    );
  }

  if (expr is PostfixExpression) {
    return PostfixExpressionNode(
      operand: _convertExpression(expr.operand, source),
      operator: expr.operator.lexeme,
      operatorSpan: SourceSpan(
        offset: expr.operator.offset,
        length: expr.operator.length,
      ),
      sourceSpan: span,
    );
  }

  if (expr is PropertyAccess) {
    final target = expr.target;
    return PropertyAccessExpressionNode(
      target: target == null ? null : _convertExpression(target, source),
      operator: expr.operator.lexeme,
      operatorSpan: SourceSpan(
        offset: expr.operator.offset,
        length: expr.operator.length,
      ),
      propertyName: expr.propertyName.name,
      propertyNameSpan: SourceSpan(
        offset: expr.propertyName.offset,
        length: expr.propertyName.length,
      ),
      sourceSpan: span,
    );
  }

  if (expr is PrefixedIdentifier) {
    return PrefixedIdentifierExpressionNode(
      prefix: expr.prefix.name,
      prefixSpan:
          SourceSpan(offset: expr.prefix.offset, length: expr.prefix.length),
      periodSpan: SourceSpan(
        offset: expr.period.offset,
        length: expr.period.length,
      ),
      identifier: expr.identifier.name,
      identifierSpan: SourceSpan(
        offset: expr.identifier.offset,
        length: expr.identifier.length,
      ),
      sourceSpan: span,
    );
  }

  if (expr is IndexExpression) {
    final target = expr.target;
    return IndexExpressionExpressionNode(
      target: target == null ? null : _convertExpression(target, source),
      questionSpan: expr.question == null
          ? null
          : SourceSpan(
              offset: expr.question!.offset,
              length: expr.question!.length,
            ),
      leftBracketSpan: SourceSpan(
        offset: expr.leftBracket.offset,
        length: expr.leftBracket.length,
      ),
      index: _convertExpression(expr.index, source),
      rightBracketSpan: SourceSpan(
        offset: expr.rightBracket.offset,
        length: expr.rightBracket.length,
      ),
      sourceSpan: span,
    );
  }

  if (expr is InstanceCreationExpression) {
    final ctorName = expr.constructorName;
    final args = expr.argumentList;
    return InstanceCreationExpressionNode(
      keywordSpan: expr.keyword == null
          ? null
          : SourceSpan(
              offset: expr.keyword!.offset,
              length: expr.keyword!.length,
            ),
      constructorNameSource: source.substring(
        ctorName.offset,
        ctorName.offset + ctorName.length,
      ),
      constructorNameSpan: SourceSpan(
        offset: ctorName.offset,
        length: ctorName.length,
      ),
      argumentsSource: source.substring(args.offset, args.offset + args.length),
      argumentsSpan: SourceSpan(offset: args.offset, length: args.length),
      sourceSpan: span,
    );
  }

  if (expr is AsExpression) {
    return AsExpressionNode(
      expression: _convertExpression(expr.expression, source),
      asKeywordSpan: SourceSpan(
        offset: expr.asOperator.offset,
        length: expr.asOperator.length,
      ),
      typeSource: source.substring(
        expr.type.offset,
        expr.type.offset + expr.type.length,
      ),
      typeSpan: SourceSpan(offset: expr.type.offset, length: expr.type.length),
      sourceSpan: span,
    );
  }

  if (expr is IsExpression) {
    return IsExpressionNode(
      expression: _convertExpression(expr.expression, source),
      isKeywordSpan: SourceSpan(
        offset: expr.isOperator.offset,
        length: expr.isOperator.length,
      ),
      notKeywordSpan: expr.notOperator == null
          ? null
          : SourceSpan(
              offset: expr.notOperator!.offset,
              length: expr.notOperator!.length,
            ),
      typeSource: source.substring(
        expr.type.offset,
        expr.type.offset + expr.type.length,
      ),
      typeSpan: SourceSpan(offset: expr.type.offset, length: expr.type.length),
      sourceSpan: span,
    );
  }

  return OpaqueExpressionNode(sourceText: raw, sourceSpan: span);
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
