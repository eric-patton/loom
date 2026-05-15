import 'package:analyzer/dart/analysis/utilities.dart';
// Hide analyzer's `ClassMember` to avoid clashing with the loom-side
// sealed type. (Same defensive import as `class_structure_parser.dart`.)
import 'package:analyzer/dart/ast/ast.dart' hide ClassMember;
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
  // Anything else (try/switch/do-while/...) or an unsupported control-flow
  // shape — preserve verbatim.
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
