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

  final block = body.block;
  final outerSpan = SourceSpan(offset: block.offset, length: block.length);
  final innerStart = block.leftBracket.offset + block.leftBracket.length;
  final innerLength = block.rightBracket.offset - innerStart;
  final innerSpan = SourceSpan(offset: innerStart, length: innerLength);

  final statements = <StatementNode>[];
  for (final stmt in block.statements) {
    statements.add(_convertStatement(stmt, source));
  }

  return FunctionBodyModel(
    bodySpan: outerSpan,
    innerSpan: innerSpan,
    statements: statements,
    diagnostics: diagnostics,
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
  // Anything else (if/for/while/try/switch/...) — preserve verbatim.
  return OpaqueStatementNode(
    sourceText: source.substring(stmt.offset, stmt.offset + stmt.length),
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
