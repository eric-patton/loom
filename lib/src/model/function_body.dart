import 'node.dart' show ParseDiagnostic;
import 'source_span.dart';

export 'node.dart' show ParseDiagnostic;

/// A modeled Dart function body (the block inside `{...}` of a method,
/// constructor, top-level function, or anonymous closure).
///
/// M8.0a first slice models three statement kinds (variable
/// declarations, expression statements, return statements) and treats
/// everything else as `OpaqueStatement`. Control flow (if/for/while/
/// switch/try) ships in later M8.x slices.
///
/// **Third separate sealed hierarchy in the kernel.** Following the
/// pattern set by `ModelNode` (constructor-tree nodes) and
/// `ClassMember` (flat class-member list), `StatementNode` is its own
/// sealed root. Function bodies are a different shape entirely — a
/// sequence of typed statements — and forcing them into either existing
/// hierarchy would dilute the semantics of both.
class FunctionBodyModel {
  const FunctionBodyModel({
    required this.body,
    this.diagnostics = const <ParseDiagnostic>[],
  });

  /// The function's top-level statement block. Always present.
  final StatementBlock body;

  final List<ParseDiagnostic> diagnostics;

  /// Backward-compat shortcut to the top-level statement list.
  List<StatementNode> get statements => body.statements;

  /// Backward-compat shortcut to the brace-inclusive body span.
  SourceSpan get bodySpan => body.blockSpan;

  /// Backward-compat shortcut to the brace-exclusive inner span.
  SourceSpan get innerSpan => body.innerSpan;

  @override
  String toString() => 'FunctionBodyModel(${statements.length} statement(s)'
      '${diagnostics.isEmpty ? '' : ', ${diagnostics.length} diagnostic(s)'})';
}

/// A `{ ... }` block of statements. Shared concept between
/// `FunctionBodyModel.body` and the then/else blocks of an
/// `IfStatementNode` (and, future M8.x slices, for/while/try blocks).
///
/// Extracted in M8.0b once if-statement modeling forced the statement-
/// list ops to work recursively. Same role as `ListSlotStyle` in the
/// widget catalog — captures the surrounding-source structure so that
/// `addStatement` / `removeStatement` can target the right insertion
/// point regardless of how deeply nested the block is.
///
/// **Brace-less variant (M8.0e):** switch-case bodies in Dart don't
/// have their own `{ ... }` — the body runs from after the `case X:`
/// colon to the start of the next case/default or to the switch's `}`.
/// For those, the same `StatementBlock` is reused with `hasBraces:
/// false`. `blockSpan` and `innerSpan` are equal in that case (both
/// covering just the statement run, no braces).
class StatementBlock {
  StatementBlock({
    required this.blockSpan,
    required this.innerSpan,
    required List<StatementNode> statements,
    this.hasBraces = true,
  }) : statements = List.unmodifiable(statements);

  /// Span of the full block. For braced blocks (function bodies, if/
  /// for/while/do/try bodies), this includes the surrounding `{` and
  /// `}`. For brace-less switch-case bodies, this is just the statement
  /// run (same as `innerSpan`).
  final SourceSpan blockSpan;

  /// Span of the block's interior. For braced blocks, this is between
  /// `{` and `}` (exclusive of the braces themselves). For brace-less
  /// switch-case bodies, identical to `blockSpan`. Used as the anchor
  /// for `addStatement` when the block is otherwise empty.
  final SourceSpan innerSpan;

  /// Statements in source order. Pattern-match on subtype to distinguish
  /// declared variables, expression statements, return statements, and
  /// (M8.0b+) control-flow statements.
  final List<StatementNode> statements;

  /// Whether this block is delimited by `{ ... }`. True for function
  /// bodies and braced control-flow bodies; false for switch-case bodies.
  ///
  /// Affects `addStatement`'s empty-block path — brace-less blocks insert
  /// at the start of the body without re-emitting a closing brace.
  final bool hasBraces;

  @override
  String toString() => 'StatementBlock(${statements.length} statement(s)'
      '${hasBraces ? '' : ', brace-less'})';
}

/// Base type for a function-body statement.
///
/// Sealed across the four kinds the M8.0a parser produces. Adding more
/// kinds (`IfStatement`, `ForStatement`, etc.) is a sealed-hierarchy
/// extension and forces exhaustiveness updates at every switch site —
/// same trade-off the constructor-tree `ModelNode` makes.
sealed class StatementNode {
  const StatementNode();

  /// Span of the full statement, including any trailing `;` and (for
  /// block-bodied statements) the closing brace.
  SourceSpan get sourceSpan;
}

/// A `var x = 1;` / `final int y = 2;` / `late T z;` declaration.
///
/// A single source declaration may declare multiple variables
/// (`var a = 1, b = 2;`), each surfaced as a `DeclaredVariable` within
/// the same statement. The qualifier flags (`isFinal` / `isVar` /
/// `isLate` / `isConst`) and type apply to the whole declaration.
class VariableDeclarationStatementNode extends StatementNode {
  VariableDeclarationStatementNode({
    required this.typeName,
    required this.typeSpan,
    required this.isFinal,
    required this.isVar,
    required this.isLate,
    required this.isConst,
    required List<DeclaredVariable> variables,
    required this.sourceSpan,
  }) : variables = List.unmodifiable(variables);

  final String? typeName;
  final SourceSpan? typeSpan;

  final bool isFinal;
  final bool isVar;
  final bool isLate;
  final bool isConst;

  final List<DeclaredVariable> variables;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() {
    final qualifiers = <String>[
      if (isLate) 'late',
      if (isFinal) 'final',
      if (isVar) 'var',
      if (isConst) 'const',
    ];
    final type = typeName ?? '';
    final names = variables.map((v) => v.name).join(', ');
    return 'VariableDeclarationStatementNode(${qualifiers.join(' ')}'
        '${qualifiers.isNotEmpty ? ' ' : ''}'
        '$type${type.isNotEmpty ? ' ' : ''}'
        '$names)';
  }
}

/// A single variable within a `VariableDeclarationStatementNode`.
///
/// Mirrors what `ClassFieldNode` captures for class fields, minus the
/// class-only `isStatic` flag. Init expressions are raw source text;
/// M8.3 adds a structured `initializerExpression: ExpressionNode?`
/// alongside.
class DeclaredVariable {
  const DeclaredVariable({
    required this.name,
    required this.nameSpan,
    required this.initializerSource,
    required this.initializerSpan,
    this.initializerExpression,
    this.initializerSwitchExpression,
  });

  final String name;
  final SourceSpan nameSpan;
  final String? initializerSource;
  final SourceSpan? initializerSpan;

  /// Structured expression view of the initializer (M8.3). Non-null
  /// whenever [initializerSource] is non-null; falls back to
  /// `OpaqueExpressionNode` for kinds not yet modeled.
  final ExpressionNode? initializerExpression;

  /// Structured view when the initializer IS a top-level switch
  /// expression. Null otherwise. The raw `initializerSource` is always
  /// present; this field is an optional structured overlay (M8.0h).
  final SwitchExpressionNode? initializerSwitchExpression;

  @override
  String toString() => 'DeclaredVariable($name'
      '${initializerSource == null ? '' : ' = $initializerSource'})';
}

/// A standalone expression used as a statement — `print(x);`,
/// `x = 5;`, `await fetch();`, `someInstance.method();`.
///
/// M8.0a captured the expression as raw `expressionSource` only.
/// M8.0h added the optional `switchExpression` structured overlay
/// (when the expression IS a switch expression). M8.2 adds a more
/// general `expression: ExpressionNode` structured view modeling
/// five expression kinds (identifier, literal, method invocation,
/// binary, opaque catch-all).
///
/// Both the raw `expressionSource` and the structured `expression`
/// are always present; existing callers using `expressionSource`
/// continue to work.
class ExpressionStatementNode extends StatementNode {
  const ExpressionStatementNode({
    required this.expressionSource,
    required this.expressionSpan,
    required this.sourceSpan,
    required this.expression,
    this.switchExpression,
  });

  /// Raw source text of the expression (no trailing `;`).
  final String expressionSource;

  /// Span of just the expression (excludes the trailing `;`).
  final SourceSpan expressionSpan;

  /// Span of the full statement including the trailing `;`.
  @override
  final SourceSpan sourceSpan;

  /// Structured expression (M8.2). Always non-null; falls back to
  /// `OpaqueExpression` for kinds not modeled in the M8.2 first slice.
  final ExpressionNode expression;

  /// Structured view when the expression IS a top-level switch
  /// expression. Null otherwise. (M8.0h)
  final SwitchExpressionNode? switchExpression;

  @override
  String toString() {
    final preview = expressionSource.length > 40
        ? '${expressionSource.substring(0, 40).replaceAll('\n', '\\n')}...'
        : expressionSource.replaceAll('\n', '\\n');
    return 'ExpressionStatementNode("$preview")';
  }
}

/// A `return [expr];` statement. The expression is optional (bare
/// `return;` in `void` functions).
///
/// M8.3 adds a structured `returnedExpression: ExpressionNode?`
/// alongside the raw `expressionSource`. Non-null whenever
/// `expressionSource` is non-null.
class ReturnStatementNode extends StatementNode {
  const ReturnStatementNode({
    required this.expressionSource,
    required this.expressionSpan,
    required this.sourceSpan,
    this.returnedExpression,
    this.switchExpression,
  });

  /// Returned expression as raw source, or null for bare `return;`.
  final String? expressionSource;
  final SourceSpan? expressionSpan;

  /// Span of the full statement including `return` and `;`.
  @override
  final SourceSpan sourceSpan;

  /// Structured expression view of the returned expression (M8.3).
  /// Non-null whenever [expressionSource] is non-null; falls back to
  /// `OpaqueExpressionNode` for kinds not yet modeled.
  final ExpressionNode? returnedExpression;

  /// Structured view when the returned expression IS a top-level
  /// switch expression. Null otherwise. (M8.0h)
  final SwitchExpressionNode? switchExpression;

  @override
  String toString() => 'ReturnStatementNode('
      '${expressionSource ?? ''})';
}

/// A modeled `if (cond) { ... } [else if (...) { ... }]* [else { ... }]?`
/// statement.
///
/// **Scope:** fully-braced if/else-if/else chains. Bare-statement bodies
/// (`if (cond) doIt();`) fall through to `OpaqueStatementNode` — most
/// real-world Dart uses braces.
///
/// The condition is captured as raw source — expression structure is
/// not modeled. The then/else bodies are full `StatementBlock`s so
/// existing statement-list ops (`addStatement`, `removeStatement`,
/// etc.) work recursively on them.
///
/// **Else-if representation (M8.0c):** for `if A {} else if B {} else {}`,
/// the outer node has `elseIf` set to a nested `IfStatementNode` whose
/// own `elseBlock` holds the terminal `else { ... }`. At most one of
/// `elseIf` / `elseBlock` is non-null on any given node.
class IfStatementNode extends StatementNode {
  const IfStatementNode({
    required this.ifKeywordSpan,
    required this.conditionSource,
    required this.conditionSpan,
    required this.condition,
    required this.thenBlock,
    required this.elseKeywordSpan,
    required this.elseBlock,
    required this.elseIf,
    required this.sourceSpan,
  });

  /// Span of the `if` keyword token.
  final SourceSpan ifKeywordSpan;

  /// The condition expression as raw source text (without surrounding
  /// parens).
  final String conditionSource;

  /// Span of just the condition expression (excluding the `(` and `)`).
  final SourceSpan conditionSpan;

  /// Structured expression view of the condition (M8.3). Always
  /// non-null; falls back to `OpaqueExpressionNode` for kinds not yet
  /// modeled.
  final ExpressionNode condition;

  /// The `{ ... }` block executed when the condition is true.
  final StatementBlock thenBlock;

  /// Span of the `else` keyword token, when an `else` clause is present
  /// (either `else { ... }` OR `else if (...) { ... }`). Null otherwise.
  final SourceSpan? elseKeywordSpan;

  /// The terminal `else { ... }` block, or null if there's no terminal
  /// `else` clause (no else at all, or the chain ends with an `else if`
  /// without a final else).
  ///
  /// Invariant: at most one of `elseBlock` / `elseIf` is non-null.
  final StatementBlock? elseBlock;

  /// The next `else if (...) { ... }` branch in the chain, or null. When
  /// non-null, this `IfStatementNode` is the "else-if subordinate" of the
  /// outer if-statement; its `sourceSpan` starts at its own `if` keyword,
  /// NOT at the `else` keyword that introduces it.
  ///
  /// Invariant: at most one of `elseBlock` / `elseIf` is non-null.
  final IfStatementNode? elseIf;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() {
    final tail = elseIf != null
        ? ', elseIf=$elseIf'
        : elseBlock != null
            ? ', ${elseBlock!.statements.length} else-stmt(s)'
            : '';
    return 'IfStatementNode('
        'cond=$conditionSource, '
        '${thenBlock.statements.length} then-stmt(s)'
        '$tail)';
  }
}

/// A modeled `for (header) { body }` statement.
///
/// Covers c-style `for (var i = 0; i < n; i++)`, for-each
/// `for (var x in iter)`, `for (final T x in iter)`, and pattern-for
/// forms. M8.0c captured the entire parenthesized header as raw
/// source; M8.2 adds a structured `header: ForLoopHeader` field
/// alongside it for callers that want to edit the header's pieces.
///
/// Only fully-braced bodies are modeled; a bare-statement body
/// (`for (x in xs) f(x);`) falls through to `OpaqueStatementNode`.
class ForStatementNode extends StatementNode {
  const ForStatementNode({
    required this.forKeywordSpan,
    required this.awaitKeywordSpan,
    required this.headerSource,
    required this.headerSpan,
    required this.header,
    required this.body,
    required this.sourceSpan,
  });

  /// Span of the `for` keyword token.
  final SourceSpan forKeywordSpan;

  /// Span of the `await` keyword when this is an `await for (...)`
  /// (asynchronous for-each); null otherwise.
  final SourceSpan? awaitKeywordSpan;

  /// Raw source of the header, INCLUDING the surrounding `(` and `)`.
  /// E.g. `(var i = 0; i < n; i++)`, `(final user in users)`.
  /// Always present; the structured view is in [header].
  final String headerSource;

  /// Span covering the parenthesized header.
  final SourceSpan headerSpan;

  /// Structured header (M8.2). Either `CStyleForHeader`,
  /// `ForEachHeader`, or `OpaqueForLoopHeader` (pattern-for variants).
  /// Always non-null.
  final ForLoopHeader header;

  /// The `{ ... }` block of the loop body.
  final StatementBlock body;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() => 'ForStatementNode('
      'header=$headerSource, '
      '${body.statements.length} body-stmt(s))';
}

/// A modeled `while (cond) { body }` statement.
///
/// Only fully-braced bodies are modeled; a bare-statement body
/// (`while (cond) f();`) falls through to `OpaqueStatementNode`.
/// The condition is captured as raw source. `do { } while (cond);`
/// is currently opaque — different shape, deferred.
class WhileStatementNode extends StatementNode {
  const WhileStatementNode({
    required this.whileKeywordSpan,
    required this.conditionSource,
    required this.conditionSpan,
    required this.condition,
    required this.body,
    required this.sourceSpan,
  });

  /// Span of the `while` keyword token.
  final SourceSpan whileKeywordSpan;

  /// The condition expression as raw source text (without surrounding
  /// parens).
  final String conditionSource;

  /// Span of just the condition expression (excluding the `(` and `)`).
  final SourceSpan conditionSpan;

  /// Structured expression view of the condition (M8.3). Always
  /// non-null.
  final ExpressionNode condition;

  /// The `{ ... }` block of the loop body.
  final StatementBlock body;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() => 'WhileStatementNode('
      'cond=$conditionSource, '
      '${body.statements.length} body-stmt(s))';
}

/// A modeled `do { body } while (cond);` statement.
///
/// Shape mirrors `WhileStatementNode` but with the condition evaluated
/// AFTER the body. Only fully-braced bodies are modeled; a bare-statement
/// body falls through to `OpaqueStatementNode`.
class DoStatementNode extends StatementNode {
  const DoStatementNode({
    required this.doKeywordSpan,
    required this.body,
    required this.whileKeywordSpan,
    required this.conditionSource,
    required this.conditionSpan,
    required this.condition,
    required this.sourceSpan,
  });

  /// Span of the `do` keyword token.
  final SourceSpan doKeywordSpan;

  /// The `{ ... }` block of the loop body.
  final StatementBlock body;

  /// Span of the trailing `while` keyword token.
  final SourceSpan whileKeywordSpan;

  /// The condition expression as raw source text (without surrounding
  /// parens).
  final String conditionSource;

  /// Structured expression view of the condition (M8.3). Always
  /// non-null.
  final ExpressionNode condition;

  /// Span of just the condition expression (excluding the `(` and `)`).
  final SourceSpan conditionSpan;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() => 'DoStatementNode('
      '${body.statements.length} body-stmt(s), '
      'cond=$conditionSource)';
}

/// A modeled `try { body } [on T] [catch (e, s)] { handler } [finally { cleanup }]`
/// statement.
///
/// Multi-clause: a `tryBlock`, zero or more `CatchClauseNode`s, and an
/// optional `finallyBlock`. Per the Dart grammar, every try statement
/// has at least one catch clause OR a finally clause.
///
/// Each block (try body, each catch handler, finally) is a full
/// `StatementBlock` so the existing statement-list ops apply
/// recursively without special-casing.
class TryStatementNode extends StatementNode {
  TryStatementNode({
    required this.tryKeywordSpan,
    required this.tryBlock,
    required List<CatchClauseNode> catchClauses,
    required this.finallyKeywordSpan,
    required this.finallyBlock,
    required this.sourceSpan,
  }) : catchClauses = List.unmodifiable(catchClauses);

  /// Span of the `try` keyword token.
  final SourceSpan tryKeywordSpan;

  /// The `{ ... }` block executed inside the try.
  final StatementBlock tryBlock;

  /// Each `on T` / `catch (e [, s])` clause in source order. May be
  /// empty when only a `finally` clause is present.
  final List<CatchClauseNode> catchClauses;

  /// Span of the `finally` keyword token when present, null otherwise.
  final SourceSpan? finallyKeywordSpan;

  /// The `{ ... }` block for the `finally` clause, or null when absent.
  final StatementBlock? finallyBlock;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() => 'TryStatementNode('
      '${tryBlock.statements.length} try-stmt(s), '
      '${catchClauses.length} catch-clause(s)'
      '${finallyBlock == null ? '' : ', finally'})';
}

/// A single `on T` / `catch (e [, s])` clause within a `TryStatementNode`.
///
/// Dart catch clauses come in three shapes:
///   * `on SomeType { ... }` — type-only, no exception variable.
///   * `catch (e) { ... }` — variable, no type.
///   * `catch (e, s) { ... }` — exception + stack trace variables.
///   * `on SomeType catch (e) { ... }` (and `... catch (e, s)`) — both.
///
/// The exception type is captured as raw source (no expression-internal
/// structure modeled). Either or both of `exceptionType` / the catch
/// variables may be absent.
class CatchClauseNode {
  const CatchClauseNode({
    required this.onKeywordSpan,
    required this.exceptionTypeSource,
    required this.exceptionTypeSpan,
    required this.catchKeywordSpan,
    required this.exceptionParameterName,
    required this.exceptionParameterSpan,
    required this.stackTraceParameterName,
    required this.stackTraceParameterSpan,
    required this.body,
    required this.sourceSpan,
  });

  /// Span of the `on` keyword when present (type-typed catch clauses).
  final SourceSpan? onKeywordSpan;

  /// Raw source of the exception type (e.g. `FormatException`,
  /// `MyError<int>`); null when the clause has no `on T` part.
  final String? exceptionTypeSource;
  final SourceSpan? exceptionTypeSpan;

  /// Span of the `catch` keyword when present.
  final SourceSpan? catchKeywordSpan;

  /// Name of the exception variable (e.g. `e` in `catch (e, s)`), or
  /// null when the clause has no `catch (...)` part.
  final String? exceptionParameterName;
  final SourceSpan? exceptionParameterSpan;

  /// Name of the stack trace variable (the second `catch` parameter),
  /// or null when absent.
  final String? stackTraceParameterName;
  final SourceSpan? stackTraceParameterSpan;

  /// The `{ ... }` block for this catch's handler.
  final StatementBlock body;

  /// Full span of this catch clause from `on` / `catch` through its
  /// closing brace.
  final SourceSpan sourceSpan;

  @override
  String toString() {
    final parts = <String>[
      if (exceptionTypeSource != null) 'on $exceptionTypeSource',
      if (exceptionParameterName != null)
        'catch ($exceptionParameterName'
            '${stackTraceParameterName == null ? '' : ', '
                '$stackTraceParameterName'})',
    ];
    return 'CatchClauseNode(${parts.join(' ')}, '
        '${body.statements.length} stmt(s))';
  }
}

/// A modeled `throw expr;` statement.
///
/// Detected when an `ExpressionStatement`'s expression is a
/// `ThrowExpression`. A `throw` buried inside a larger expression
/// (e.g. `cond ? value : throw Foo()`) stays opaque within the host
/// `ExpressionStatementNode`'s `expressionSource`.
class ThrowStatementNode extends StatementNode {
  const ThrowStatementNode({
    required this.throwKeywordSpan,
    required this.expressionSource,
    required this.expressionSpan,
    required this.sourceSpan,
    required this.thrownExpression,
  });

  /// Span of the `throw` keyword token.
  final SourceSpan throwKeywordSpan;

  /// Raw source of the thrown expression (no surrounding semicolon).
  /// Unlike `return`, throw always has an expression — the grammar
  /// requires it.
  final String expressionSource;
  final SourceSpan expressionSpan;

  /// Span of the full statement including `throw` and `;`.
  @override
  final SourceSpan sourceSpan;

  /// Structured expression view of the thrown expression (M8.3).
  /// Always non-null; falls back to `OpaqueExpressionNode` for kinds
  /// not yet modeled.
  final ExpressionNode thrownExpression;

  @override
  String toString() => 'ThrowStatementNode($expressionSource)';
}

/// A modeled `switch (expr) { ...members... }` statement.
///
/// Captures the switched expression as raw source plus an ordered list
/// of `SwitchMemberNode`s. Switch **expressions** (the `switch (x) { 1
/// => 'a', _ => 'b' }` form) live inside expression context and are
/// NOT statements — they stay opaque inside the host expression's
/// source (no separate node).
///
/// **Pattern surface (M8.0h scope):** all 14 Dart 3 pattern kinds are
/// modeled structurally — constant, declared variable, wildcard,
/// logical-or, object, record, list, map, relational, null-check,
/// null-assert, cast, parenthesized, logical-and. `OpaquePatternNode`
/// is now only a safety fallback for unrecognized analyzer shapes.
/// Each `SwitchCaseNode` carries BOTH the raw `patternSource` string
/// (M8.0e, for callers that just want the verbatim text) AND a
/// structured `pattern: PatternNode` for pattern-aware editing.
class SwitchStatementNode extends StatementNode {
  SwitchStatementNode({
    required this.switchKeywordSpan,
    required this.expressionSource,
    required this.expressionSpan,
    required this.leftBracketSpan,
    required List<SwitchMemberNode> members,
    required this.rightBracketSpan,
    required this.sourceSpan,
  }) : members = List.unmodifiable(members);

  /// Span of the `switch` keyword token.
  final SourceSpan switchKeywordSpan;

  /// Raw source of the switched expression (without surrounding parens).
  final String expressionSource;

  /// Span of just the expression (excludes the `(` and `)`).
  final SourceSpan expressionSpan;

  /// Span of the switch body's opening `{`.
  final SourceSpan leftBracketSpan;

  /// Switch members (cases + default) in source order.
  final List<SwitchMemberNode> members;

  /// Span of the switch body's closing `}`.
  final SourceSpan rightBracketSpan;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() => 'SwitchStatementNode('
      'on=$expressionSource, '
      '${members.length} member(s))';
}

/// Base type for a member of a `SwitchStatementNode`. Sealed across
/// `SwitchCaseNode` and `SwitchDefaultNode`. Pattern-match on subtype.
///
/// Each member has its own brace-less `StatementBlock` body — the
/// statements after the `:` colon up to the next case/default keyword
/// or the switch's closing `}`.
sealed class SwitchMemberNode {
  const SwitchMemberNode();

  /// Span of just the introducer keyword (`case` or `default`).
  SourceSpan get keywordSpan;

  /// Span of the `:` colon separating the case header from its body.
  SourceSpan get colonSpan;

  /// The case/default's statement body, brace-less (`hasBraces: false`).
  StatementBlock get body;

  /// Full span of this member from its keyword (or first label) through
  /// the last statement (or the colon, when the body is empty).
  SourceSpan get sourceSpan;
}

/// A `case [pattern] [when guard]: ...statements...` member.
///
/// Covers both the legacy `case constantExpr:` form and the Dart 3
/// `case pattern [when guard]:` pattern-case form. Both shapes capture
/// the pattern/expression as opaque source under `patternSource`. Legacy
/// cases have `whenGuardSource == null`.
class SwitchCaseNode extends SwitchMemberNode {
  const SwitchCaseNode({
    required this.keywordSpan,
    required this.patternSource,
    required this.patternSpan,
    required this.pattern,
    required this.whenKeywordSpan,
    required this.whenGuardSource,
    required this.whenGuardSpan,
    required this.colonSpan,
    required this.body,
    required this.sourceSpan,
  });

  /// Span of the `case` keyword token.
  @override
  final SourceSpan keywordSpan;

  /// Raw source of the pattern (Dart 3) or constant expression (legacy).
  /// Always present; mirrors the verbatim text. For the structured
  /// view, use [pattern].
  final String patternSource;
  final SourceSpan patternSpan;

  /// Structured pattern. M8.0f models four pattern kinds (constant,
  /// declared variable, wildcard, logical-or); other pattern kinds fall
  /// through to `OpaquePatternNode`. Always non-null.
  final PatternNode pattern;

  /// Span of the `when` keyword token, when a guard is present; null
  /// otherwise. Only valid on pattern cases (Dart 3); legacy `case`
  /// forms can't have guards.
  final SourceSpan? whenKeywordSpan;

  /// Raw source of the `when` guard expression (no `when` keyword);
  /// null when there's no guard.
  final String? whenGuardSource;
  final SourceSpan? whenGuardSpan;

  @override
  final SourceSpan colonSpan;

  @override
  final StatementBlock body;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() {
    final guard = whenGuardSource == null ? '' : ' when $whenGuardSource';
    return 'SwitchCaseNode('
        'case $patternSource$guard:, '
        '${body.statements.length} stmt(s))';
  }
}

/// A `default: ...statements...` member of a switch statement.
class SwitchDefaultNode extends SwitchMemberNode {
  const SwitchDefaultNode({
    required this.keywordSpan,
    required this.colonSpan,
    required this.body,
    required this.sourceSpan,
  });

  /// Span of the `default` keyword token.
  @override
  final SourceSpan keywordSpan;

  @override
  final SourceSpan colonSpan;

  @override
  final StatementBlock body;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() => 'SwitchDefaultNode(${body.statements.length} stmt(s))';
}

/// A modeled `yield expr;` or `yield* expr;` statement.
///
/// Used inside `sync*` / `async*` generator functions. The `*` form
/// delegates iteration to another iterable/stream; the bare form
/// yields a single value. The expression is captured as raw source.
class YieldStatementNode extends StatementNode {
  const YieldStatementNode({
    required this.yieldKeywordSpan,
    required this.starSpan,
    required this.expressionSource,
    required this.expressionSpan,
    required this.sourceSpan,
    required this.yieldedExpression,
  });

  final SourceSpan yieldKeywordSpan;

  /// Span of the `*` token, when present (`yield*` form). Null
  /// otherwise.
  final SourceSpan? starSpan;

  final String expressionSource;
  final SourceSpan expressionSpan;

  @override
  final SourceSpan sourceSpan;

  /// Structured expression view of the yielded expression (M8.3).
  /// Always non-null; falls back to `OpaqueExpressionNode` for kinds
  /// not yet modeled.
  final ExpressionNode yieldedExpression;

  /// True when this is a `yield*` (delegating yield).
  bool get isDelegating => starSpan != null;

  @override
  String toString() => 'YieldStatementNode('
      '${isDelegating ? 'yield* ' : 'yield '}$expressionSource)';
}

/// A modeled `break;` or `break label;` statement.
class BreakStatementNode extends StatementNode {
  const BreakStatementNode({
    required this.breakKeywordSpan,
    required this.labelName,
    required this.labelSpan,
    required this.sourceSpan,
  });

  final SourceSpan breakKeywordSpan;

  /// The target label name (e.g. `'outer'` in `break outer;`), or null
  /// for a bare `break;`.
  final String? labelName;
  final SourceSpan? labelSpan;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() =>
      'BreakStatementNode(${labelName == null ? 'break' : 'break $labelName'})';
}

/// A modeled `continue;` or `continue label;` statement.
class ContinueStatementNode extends StatementNode {
  const ContinueStatementNode({
    required this.continueKeywordSpan,
    required this.labelName,
    required this.labelSpan,
    required this.sourceSpan,
  });

  final SourceSpan continueKeywordSpan;

  /// The target label name (e.g. `'outer'` in `continue outer;`), or
  /// null for a bare `continue;`.
  final String? labelName;
  final SourceSpan? labelSpan;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() => 'ContinueStatementNode('
      '${labelName == null ? 'continue' : 'continue $labelName'})';
}

/// A modeled `label: stmt;` statement. A statement can carry MULTIPLE
/// labels stacked (`outer: inner: while (true) {...}`) — labels are
/// captured in source order.
class LabeledStatementNode extends StatementNode {
  LabeledStatementNode({
    required List<LabelNode> labels,
    required this.statement,
    required this.sourceSpan,
  }) : labels = List.unmodifiable(labels);

  /// Labels in source order. Length >= 1 (otherwise this wouldn't be
  /// a labeled statement at all).
  final List<LabelNode> labels;

  /// The inner (labeled) statement. Itself a structured `StatementNode`
  /// — typically a loop, switch, or block that the labels target.
  final StatementNode statement;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() =>
      'LabeledStatementNode(${labels.map((l) => l.name).join(', ')}: '
      '$statement)';
}

/// A single `name:` label preceding a labeled statement.
class LabelNode {
  const LabelNode({
    required this.name,
    required this.nameSpan,
    required this.colonSpan,
    required this.sourceSpan,
  });

  final String name;
  final SourceSpan nameSpan;
  final SourceSpan colonSpan;
  final SourceSpan sourceSpan;

  @override
  String toString() => 'LabelNode($name:)';
}

/// A statement kind not yet modeled. With M8.1 all Dart statement
/// shapes the parser knows about have structural modeling; this is
/// now only a safety fallback for unrecognized future shapes.
class OpaqueStatementNode extends StatementNode {
  const OpaqueStatementNode({
    required this.sourceText,
    required this.sourceSpan,
  });

  /// Verbatim source bytes for this statement.
  final String sourceText;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() {
    final preview = sourceText.length > 40
        ? '${sourceText.substring(0, 40).replaceAll('\n', '\\n')}...'
        : sourceText.replaceAll('\n', '\\n');
    return 'OpaqueStatementNode(@${sourceSpan.offset}+${sourceSpan.length}, '
        '"$preview")';
  }
}

// ===========================================================================
// Pattern internals (M8.0f)
// ===========================================================================

/// Base type for a Dart pattern. Currently used by `SwitchCaseNode.pattern`;
/// later milestones can reuse this in `if-case` statements, pattern
/// variable declarations, and pattern assignments.
///
/// Sealed across five subtypes. M8.0f models the four highest-value
/// kinds structurally (constant, declared variable, wildcard, logical-
/// or); `OpaquePatternNode` is the catch-all for the rest (object,
/// record, list, map, logical-and, relational, null-check, null-assert,
/// cast, parenthesized). Same opaque-fallback pattern as
/// `OpaqueStatementNode`.
sealed class PatternNode {
  const PatternNode();

  /// Span of the full pattern in the source.
  SourceSpan get sourceSpan;
}

/// A constant pattern — `case 0:`, `case 'foo':`, `case const Foo():`,
/// `case Colors.red:`. The expression itself is opaque source.
class ConstantPatternNode extends PatternNode {
  const ConstantPatternNode({
    required this.constKeywordSpan,
    required this.expressionSource,
    required this.expressionSpan,
    required this.sourceSpan,
  });

  /// Span of the optional leading `const` keyword (for cases like
  /// `case const Foo():`); null when absent.
  final SourceSpan? constKeywordSpan;

  /// Raw source of the constant expression.
  final String expressionSource;
  final SourceSpan expressionSpan;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() => 'ConstantPatternNode($expressionSource)';
}

/// A declared variable pattern — `case int n:`, `case var x:`,
/// `case final String s:`. Binds a new variable in the case scope.
class DeclaredVariablePatternNode extends PatternNode {
  const DeclaredVariablePatternNode({
    required this.keywordSpan,
    required this.typeSource,
    required this.typeSpan,
    required this.name,
    required this.nameSpan,
    required this.sourceSpan,
  });

  /// Span of the optional leading `var` / `final` keyword; null when
  /// absent (e.g. `case int n:` has no keyword).
  final SourceSpan? keywordSpan;

  /// Raw source of the type annotation (e.g. `int`, `List<String>`),
  /// or null when no type is written (e.g. `case var x:`).
  final String? typeSource;
  final SourceSpan? typeSpan;

  /// The name of the bound variable (e.g. `n` in `case int n:`).
  final String name;
  final SourceSpan nameSpan;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() {
    final type = typeSource ?? '';
    return 'DeclaredVariablePatternNode('
        '${type.isNotEmpty ? '$type ' : ''}$name)';
  }
}

/// A wildcard pattern — `case _:`, `case int _:`. Matches anything (or
/// anything of the given type) without binding a variable.
class WildcardPatternNode extends PatternNode {
  const WildcardPatternNode({
    required this.keywordSpan,
    required this.typeSource,
    required this.typeSpan,
    required this.underscoreSpan,
    required this.sourceSpan,
  });

  /// Span of the optional leading `var` / `final` keyword; null when
  /// absent.
  final SourceSpan? keywordSpan;

  /// Raw source of the type annotation (e.g. `int` in `case int _:`),
  /// or null when no type is written.
  final String? typeSource;
  final SourceSpan? typeSpan;

  /// Span of the `_` token itself.
  final SourceSpan underscoreSpan;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() {
    final type = typeSource ?? '';
    return 'WildcardPatternNode(${type.isNotEmpty ? '$type ' : ''}_)';
  }
}

/// A logical-or pattern — `case 1 || 2 || 3:`, `case A || B:`.
///
/// The analyzer represents `1 || 2 || 3` as a binary tree
/// (`(1 || 2) || 3`); this model flattens the chain into a single
/// ordered list of [operands] plus a list of [operatorSpans] (one
/// `||` token between each adjacent operand pair).
class LogicalOrPatternNode extends PatternNode {
  LogicalOrPatternNode({
    required List<PatternNode> operands,
    required List<SourceSpan> operatorSpans,
    required this.sourceSpan,
  })  : operands = List.unmodifiable(operands),
        operatorSpans = List.unmodifiable(operatorSpans),
        assert(
          operands.length >= 2,
          'LogicalOrPatternNode must have at least 2 operands',
        ),
        assert(
          operatorSpans.length == operands.length - 1,
          'operatorSpans.length must equal operands.length - 1',
        );

  /// Flattened operands in source order. Length >= 2.
  final List<PatternNode> operands;

  /// Spans of the `||` tokens between adjacent operands. Length =
  /// `operands.length - 1`.
  final List<SourceSpan> operatorSpans;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() => 'LogicalOrPatternNode(${operands.length} operand(s))';
}

/// An object pattern — `case Foo(x: 1, y: var n):`, `case Foo(:var x):`,
/// `case Point(0, 0):`. Captures the class type name plus an ordered
/// list of `PatternField`s (positional + named, in source order).
///
/// The type may include type arguments (`case Result<int>(:var value):`)
/// and is captured as raw source. Fields are recursive — each field's
/// sub-pattern is a full `PatternNode`, so nested `case Foo(x: int n
/// when n > 0):` resolves through the existing `DeclaredVariablePattern`
/// path.
class ObjectPatternNode extends PatternNode {
  ObjectPatternNode({
    required this.typeNameSource,
    required this.typeNameSpan,
    required this.leftParenSpan,
    required List<PatternField> fields,
    required this.rightParenSpan,
    required this.sourceSpan,
  }) : fields = List.unmodifiable(fields);

  /// Raw source of the type name, e.g. `Point`, `Result<int>`,
  /// `prefix.MyClass`.
  final String typeNameSource;
  final SourceSpan typeNameSpan;

  /// Span of the `(` opening the field list.
  final SourceSpan leftParenSpan;

  /// Fields in source order. May be empty (`case Foo():`).
  final List<PatternField> fields;

  /// Span of the `)` closing the field list.
  final SourceSpan rightParenSpan;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() => 'ObjectPatternNode('
      '$typeNameSource, ${fields.length} field(s))';
}

/// A record pattern — `case (1, 2):`, `case (x: 1, y: var n):`,
/// `case (:var x, :var y):`. Same shape as `ObjectPatternNode` but
/// without the class-name prefix — records are structural, not
/// nominally typed.
///
/// A single-element record pattern uses a trailing comma to disambiguate
/// from a parenthesized pattern: `case (1,):` is a record, `case (1):`
/// is a parenthesized constant pattern.
class RecordPatternNode extends PatternNode {
  RecordPatternNode({
    required this.leftParenSpan,
    required List<PatternField> fields,
    required this.rightParenSpan,
    required this.sourceSpan,
  }) : fields = List.unmodifiable(fields);

  /// Span of the `(` opening the record.
  final SourceSpan leftParenSpan;

  /// Fields in source order. The record-disambiguation rule requires
  /// at least one field for a record pattern (otherwise it'd be a
  /// parenthesized pattern).
  final List<PatternField> fields;

  /// Span of the `)` closing the record.
  final SourceSpan rightParenSpan;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() => 'RecordPatternNode(${fields.length} field(s))';
}

/// A single field inside an `ObjectPatternNode` or `RecordPatternNode`.
///
/// Three field shapes are represented in a single class with nullable
/// fields (same approach as `CatchClauseNode` in M8.0d):
///   * **Positional**: `Foo(1, 2)` — `fieldName` and `colonSpan` are
///     both null.
///   * **Explicit named**: `Foo(x: 1)` — `fieldName == 'x'`,
///     `colonSpan` is the `:` after the name, `isShorthand: false`.
///   * **Shorthand named**: `Foo(:var x)` — `fieldName` is null
///     (the name is implied by the inner pattern's variable), but
///     `colonSpan` IS present (the `:` before `var x`), and
///     `isShorthand: true`.
class PatternField {
  const PatternField({
    required this.fieldName,
    required this.fieldNameSpan,
    required this.colonSpan,
    required this.isShorthand,
    required this.pattern,
    required this.sourceSpan,
  });

  /// The explicit field name (e.g. `x` in `Foo(x: 1)`), or null when
  /// the field is positional or shorthand.
  final String? fieldName;
  final SourceSpan? fieldNameSpan;

  /// Span of the `:` separator for named fields (explicit OR shorthand);
  /// null for positional fields.
  final SourceSpan? colonSpan;

  /// True when the field uses shorthand `:varX` syntax (the field name
  /// is implied by the inner pattern's variable).
  final bool isShorthand;

  /// The sub-pattern for this field. Recursive — can be any
  /// `PatternNode` kind.
  final PatternNode pattern;

  /// Full span of this field including its name + colon + sub-pattern.
  final SourceSpan sourceSpan;

  /// True when this field carries an explicit `name:` prefix.
  bool get isNamed => fieldName != null;

  /// True when this field has no name part at all (positional).
  bool get isPositional => fieldName == null && colonSpan == null;

  @override
  String toString() {
    if (isPositional) return 'PatternField($pattern)';
    if (isShorthand) return 'PatternField(:$pattern)';
    return 'PatternField($fieldName: $pattern)';
  }
}

/// A list pattern — `case [a, b]:`, `case [first, ...rest]:`,
/// `case <int>[1, 2, 3]:`. Captures optional type arguments source,
/// bracket spans, and an ordered list of elements (regular patterns
/// or `...` rest elements).
class ListPatternNode extends PatternNode {
  ListPatternNode({
    required this.typeArgumentsSource,
    required this.typeArgumentsSpan,
    required this.leftBracketSpan,
    required List<ListPatternElement> elements,
    required this.rightBracketSpan,
    required this.sourceSpan,
  }) : elements = List.unmodifiable(elements);

  /// Raw source of the type arguments (e.g. `<int>`), or null when no
  /// type arguments are written.
  final String? typeArgumentsSource;
  final SourceSpan? typeArgumentsSpan;

  final SourceSpan leftBracketSpan;
  final List<ListPatternElement> elements;
  final SourceSpan rightBracketSpan;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() => 'ListPatternNode(${elements.length} element(s))';
}

/// Element of a list pattern. Either a regular pattern or a rest
/// element (`...` / `...rest`).
abstract class ListPatternElement {
  SourceSpan get sourceSpan;
}

/// A regular `PatternNode`-bearing list element.
class ListPatternPatternElement implements ListPatternElement {
  const ListPatternPatternElement({
    required this.pattern,
    required this.sourceSpan,
  });
  final PatternNode pattern;
  @override
  final SourceSpan sourceSpan;
  @override
  String toString() => 'ListPatternPatternElement($pattern)';
}

/// A `...` or `...subPattern` rest element inside a list pattern.
/// The sub-pattern is optional — bare `...` matches without binding.
class ListPatternRestElement implements ListPatternElement {
  const ListPatternRestElement({
    required this.operatorSpan,
    required this.subPattern,
    required this.sourceSpan,
  });
  final SourceSpan operatorSpan;
  final PatternNode? subPattern;
  @override
  final SourceSpan sourceSpan;
  @override
  String toString() => subPattern == null
      ? 'ListPatternRestElement(...)'
      : 'ListPatternRestElement(...$subPattern)';
}

/// A map pattern — `case {'k': v, 'k2': _}:`,
/// `case <String, int>{'a': 1}:`. Entries map a key expression
/// (opaque source) to a `PatternNode` value.
class MapPatternNode extends PatternNode {
  MapPatternNode({
    required this.typeArgumentsSource,
    required this.typeArgumentsSpan,
    required this.leftBracketSpan,
    required List<MapPatternElement> elements,
    required this.rightBracketSpan,
    required this.sourceSpan,
  }) : elements = List.unmodifiable(elements);

  final String? typeArgumentsSource;
  final SourceSpan? typeArgumentsSpan;
  final SourceSpan leftBracketSpan;
  final List<MapPatternElement> elements;
  final SourceSpan rightBracketSpan;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() => 'MapPatternNode(${elements.length} element(s))';
}

/// Element of a map pattern. Either a key-value entry or a rest
/// element (rare; same `...` shape as in list patterns).
abstract class MapPatternElement {
  SourceSpan get sourceSpan;
}

/// A `key: pattern` entry inside a map pattern.
class MapPatternEntryNode implements MapPatternElement {
  const MapPatternEntryNode({
    required this.keyExpressionSource,
    required this.keyExpressionSpan,
    required this.colonSpan,
    required this.pattern,
    required this.sourceSpan,
  });

  /// Raw source of the key expression (e.g. `'foo'`, `0`, `MyEnum.a`).
  final String keyExpressionSource;
  final SourceSpan keyExpressionSpan;

  /// Span of the `:` separator.
  final SourceSpan colonSpan;

  /// The value sub-pattern.
  final PatternNode pattern;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() => 'MapPatternEntryNode($keyExpressionSource: $pattern)';
}

/// A `...` rest element inside a map pattern.
class MapPatternRestElement implements MapPatternElement {
  const MapPatternRestElement({
    required this.operatorSpan,
    required this.subPattern,
    required this.sourceSpan,
  });
  final SourceSpan operatorSpan;
  final PatternNode? subPattern;
  @override
  final SourceSpan sourceSpan;
  @override
  String toString() => 'MapPatternRestElement()';
}

/// A relational pattern — `case > 100:`, `case == foo:`, `case <= 5:`.
/// Matches values where `value <op> operand` is true.
class RelationalPatternNode extends PatternNode {
  const RelationalPatternNode({
    required this.operator,
    required this.operatorSpan,
    required this.operandSource,
    required this.operandSpan,
    required this.sourceSpan,
  });

  /// The operator token's lexeme — `==`, `!=`, `<`, `<=`, `>`, `>=`.
  final String operator;
  final SourceSpan operatorSpan;

  /// Raw source of the operand expression.
  final String operandSource;
  final SourceSpan operandSpan;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() => 'RelationalPatternNode($operator $operandSource)';
}

/// A null-check pattern — `case var x?:`, `case Foo()?:`. Matches
/// non-null values; bare `case _?:` rejects null without binding.
class NullCheckPatternNode extends PatternNode {
  const NullCheckPatternNode({
    required this.innerPattern,
    required this.operatorSpan,
    required this.sourceSpan,
  });

  final PatternNode innerPattern;

  /// Span of the trailing `?` token.
  final SourceSpan operatorSpan;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() => 'NullCheckPatternNode($innerPattern?)';
}

/// A null-assert pattern — `case var x!:`, `case Foo()!:`. Asserts
/// the value is non-null and matches the inner pattern (throws if null).
class NullAssertPatternNode extends PatternNode {
  const NullAssertPatternNode({
    required this.innerPattern,
    required this.operatorSpan,
    required this.sourceSpan,
  });

  final PatternNode innerPattern;
  final SourceSpan operatorSpan;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() => 'NullAssertPatternNode($innerPattern!)';
}

/// A cast pattern — `case var x as int:`, `case (a, b) as Pair:`.
/// Casts the value to a specific type and then matches the inner
/// pattern.
class CastPatternNode extends PatternNode {
  const CastPatternNode({
    required this.innerPattern,
    required this.asKeywordSpan,
    required this.typeSource,
    required this.typeSpan,
    required this.sourceSpan,
  });

  final PatternNode innerPattern;
  final SourceSpan asKeywordSpan;
  final String typeSource;
  final SourceSpan typeSpan;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() => 'CastPatternNode($innerPattern as $typeSource)';
}

/// A parenthesized pattern — `case (1 || 2):`. Wraps an inner pattern
/// for grouping; doesn't change matching semantics.
class ParenthesizedPatternNode extends PatternNode {
  const ParenthesizedPatternNode({
    required this.leftParenSpan,
    required this.innerPattern,
    required this.rightParenSpan,
    required this.sourceSpan,
  });

  final SourceSpan leftParenSpan;
  final PatternNode innerPattern;
  final SourceSpan rightParenSpan;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() => 'ParenthesizedPatternNode(($innerPattern))';
}

/// A logical-and pattern — `case int n && > 0:`. Matches when ALL
/// operands match. Like `LogicalOrPatternNode`, the analyzer's binary
/// tree is flattened into an ordered operand list.
class LogicalAndPatternNode extends PatternNode {
  LogicalAndPatternNode({
    required List<PatternNode> operands,
    required List<SourceSpan> operatorSpans,
    required this.sourceSpan,
  })  : operands = List.unmodifiable(operands),
        operatorSpans = List.unmodifiable(operatorSpans),
        assert(
          operands.length >= 2,
          'LogicalAndPatternNode must have at least 2 operands',
        ),
        assert(
          operatorSpans.length == operands.length - 1,
          'operatorSpans.length must equal operands.length - 1',
        );

  /// Flattened operands in source order. Length >= 2.
  final List<PatternNode> operands;

  /// Spans of the `&&` tokens between adjacent operands.
  final List<SourceSpan> operatorSpans;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() => 'LogicalAndPatternNode(${operands.length} operand(s))';
}

/// A pattern kind not yet modeled. With M8.0h, every Dart 3 pattern
/// kind has structural modeling — `OpaquePatternNode` is now only used
/// when the parser encounters an unexpected pattern shape (e.g. from a
/// future analyzer release).
class OpaquePatternNode extends PatternNode {
  const OpaquePatternNode({
    required this.sourceText,
    required this.sourceSpan,
  });

  /// Verbatim source bytes for this pattern.
  final String sourceText;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() {
    final preview = sourceText.length > 40
        ? '${sourceText.substring(0, 40).replaceAll('\n', '\\n')}...'
        : sourceText.replaceAll('\n', '\\n');
    return 'OpaquePatternNode("$preview")';
  }
}

// ===========================================================================
// Switch expressions (M8.0h)
// ===========================================================================

/// A modeled switch **expression** — `switch (x) { 1 => 'one', _ =>
/// 'other' }`. Unlike `SwitchStatementNode`, switch expressions
/// produce a value and are USED inside other expressions (variable
/// initializers, return expressions, function arguments, etc.).
///
/// **Where they appear in the model.** The parser surfaces a
/// `SwitchExpressionNode` view at three positions:
///   * `DeclaredVariable.initializerSwitchExpression` — when a
///     variable declaration's initializer is itself a switch
///     expression: `final r = switch (x) { ... };`.
///   * `ReturnStatementNode.switchExpression` — when a return's
///     expression is a switch: `return switch (x) { ... };`.
///   * `ExpressionStatementNode.switchExpression` — when an expression
///     statement IS a switch expression (rare — typically a switch
///     expression's value is discarded only in tests).
///
/// Switch expressions deeply nested inside other expressions
/// (e.g. `f(switch (x) { ... })`) are NOT surfaced — they stay opaque
/// inside the host expression's source. Surfacing them would require
/// modeling expression-internal structure, a separate large surface.
class SwitchExpressionNode {
  SwitchExpressionNode({
    required this.switchKeywordSpan,
    required this.subjectSource,
    required this.subjectSpan,
    required this.leftBracketSpan,
    required List<SwitchExpressionCaseNode> cases,
    required this.rightBracketSpan,
    required this.sourceSpan,
  }) : cases = List.unmodifiable(cases);

  /// Span of the `switch` keyword.
  final SourceSpan switchKeywordSpan;

  /// Raw source of the switched expression (no surrounding parens).
  final String subjectSource;
  final SourceSpan subjectSpan;

  final SourceSpan leftBracketSpan;
  final List<SwitchExpressionCaseNode> cases;
  final SourceSpan rightBracketSpan;

  /// Span of the full switch expression in source.
  final SourceSpan sourceSpan;

  @override
  String toString() => 'SwitchExpressionNode('
      'on=$subjectSource, ${cases.length} case(s))';
}

/// A single `pattern [when guard] => resultExpression` case in a
/// switch expression. Unlike `SwitchCaseNode` (which has a body of
/// statements), each case here has a single result expression.
class SwitchExpressionCaseNode {
  const SwitchExpressionCaseNode({
    required this.pattern,
    required this.whenKeywordSpan,
    required this.whenGuardSource,
    required this.whenGuardSpan,
    required this.arrowSpan,
    required this.resultExpressionSource,
    required this.resultExpressionSpan,
    required this.sourceSpan,
  });

  /// Structured pattern. Recursive — any `PatternNode` kind.
  final PatternNode pattern;

  /// Span of the `when` keyword when a guard is present; null otherwise.
  final SourceSpan? whenKeywordSpan;
  final String? whenGuardSource;
  final SourceSpan? whenGuardSpan;

  /// Span of the `=>` arrow token.
  final SourceSpan arrowSpan;

  /// Raw source of the result expression (no trailing comma).
  final String resultExpressionSource;
  final SourceSpan resultExpressionSpan;

  /// Full span of this case from its pattern through the result.
  final SourceSpan sourceSpan;

  @override
  String toString() => 'SwitchExpressionCaseNode('
      '$pattern => $resultExpressionSource)';
}

// ===========================================================================
// For-loop header (M8.2)
// ===========================================================================

/// Base type for a `ForStatementNode`'s parenthesized header. Sealed
/// across three subtypes:
///   * `CStyleForHeader` — `for (init; cond; updaters)`.
///   * `ForEachHeader` — `for (var x in iter)` or `for (x in iter)`.
///   * `OpaqueForLoopHeader` — pattern-for shapes
///     (`for (var (a, b) in pairs)`) or future unknown headers.
sealed class ForLoopHeader {
  const ForLoopHeader();

  /// Span of the full header including the surrounding `(` and `)`.
  SourceSpan get sourceSpan;
}

/// A c-style `for (init; condition; updaters)` header.
///
/// The init, condition, and updaters are captured as raw source
/// (each optional for init/condition; updaters is an ordered list).
/// Modeling expression internals is the M8.2 first slice and applies
/// only to top-level expression statements for now; for-loop pieces
/// stay as opaque text until concrete edits demand more.
class CStyleForHeader extends ForLoopHeader {
  CStyleForHeader({
    required this.initSource,
    required this.initSpan,
    required this.leftSeparatorSpan,
    required this.conditionSource,
    required this.conditionSpan,
    required this.rightSeparatorSpan,
    required List<String> updaterSources,
    required List<SourceSpan> updaterSpans,
    required this.sourceSpan,
  })  : updaterSources = List.unmodifiable(updaterSources),
        updaterSpans = List.unmodifiable(updaterSpans),
        assert(
          updaterSources.length == updaterSpans.length,
          'updaterSources and updaterSpans must have the same length',
        );

  /// Raw source of the init clause (e.g. `var i = 0`, `i = 0`), or
  /// null when the init is empty (`for (; cond; updater)`).
  final String? initSource;
  final SourceSpan? initSpan;

  /// Span of the first `;` separator (after init).
  final SourceSpan leftSeparatorSpan;

  /// Raw source of the condition expression, or null when absent
  /// (`for (init; ; updater)`).
  final String? conditionSource;
  final SourceSpan? conditionSpan;

  /// Span of the second `;` separator (after condition).
  final SourceSpan rightSeparatorSpan;

  /// Raw sources of the updater expressions (e.g. `['i++', 'j *= 2']`).
  /// Empty when no updaters.
  final List<String> updaterSources;
  final List<SourceSpan> updaterSpans;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() => 'CStyleForHeader('
      '${initSource ?? ''}; ${conditionSource ?? ''}; '
      '${updaterSources.join(', ')})';
}

/// A `for (var x in iter)` or `for (x in iter)` header.
///
/// Covers both shapes via a single class with `isExistingIdentifier`:
///   * **Declared variable** — `for (var x in iter)`,
///     `for (final T x in iter)`, `for (int x in iter)`. Has optional
///     keyword (`var`/`final`) and optional type annotation.
///   * **Existing identifier** — `for (x in iter)` where `x` is
///     already declared. Rare; `isExistingIdentifier == true`.
class ForEachHeader extends ForLoopHeader {
  const ForEachHeader({
    required this.keywordSpan,
    required this.typeSource,
    required this.typeSpan,
    required this.loopVariableName,
    required this.loopVariableSpan,
    required this.isExistingIdentifier,
    required this.inKeywordSpan,
    required this.iterableSource,
    required this.iterableSpan,
    required this.sourceSpan,
  });

  /// Span of the optional leading `var` / `final` / `const` keyword
  /// (declared-variable form only). Null otherwise.
  final SourceSpan? keywordSpan;

  /// Raw source of the type annotation, or null when absent.
  final String? typeSource;
  final SourceSpan? typeSpan;

  /// Name of the loop variable.
  final String loopVariableName;
  final SourceSpan loopVariableSpan;

  /// True when this is `for (x in iter)` (existing identifier),
  /// false when this is `for (var x in iter)` / `for (T x in iter)`
  /// (declares a new variable).
  final bool isExistingIdentifier;

  /// Span of the `in` keyword.
  final SourceSpan inKeywordSpan;

  /// Raw source of the iterable expression.
  final String iterableSource;
  final SourceSpan iterableSpan;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() => 'ForEachHeader('
      '${typeSource == null ? '' : '$typeSource '}'
      '$loopVariableName in $iterableSource)';
}

/// Catch-all for for-loop header shapes the parser doesn't model
/// structurally — pattern-for variants like `for (var (a, b) in pairs)`,
/// `for (final (a, b) = something; ...; ...)` etc. Preserves the
/// header source verbatim.
class OpaqueForLoopHeader extends ForLoopHeader {
  const OpaqueForLoopHeader({
    required this.headerSource,
    required this.sourceSpan,
  });

  /// Verbatim header text (including the surrounding parens).
  final String headerSource;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() => 'OpaqueForLoopHeader($headerSource)';
}

// ===========================================================================
// Expression internals — first slice (M8.2)
// ===========================================================================

/// Base type for a Dart expression. Sealed across five subtypes for
/// the M8.2 first slice — the most common shapes that appear inside
/// `ExpressionStatementNode`. Most expression kinds fall through to
/// `OpaqueExpression` for now; future milestones can promote them as
/// concrete edit needs demand.
///
/// **Scope (M8.2):** structured modeling exists only inside
/// `ExpressionStatementNode.expression`. Other expression-bearing
/// positions (variable initializers, return expressions, if conditions,
/// etc.) still use raw source. Surfacing structured expressions
/// everywhere is a separate, larger surface.
///
/// **Modeled kinds (M8.2/M8.3):**
///   * `IdentifierExpressionNode` — `x`, `print` (a bare reference).
///   * `LiteralExpressionNode` — `42`, `'hello'`, `true`, `false`,
///     `null`, `3.14`.
///   * `MethodInvocationExpressionNode` — `f(args)` or
///     `target.method(args)`.
///   * `BinaryExpressionNode` — `a + b`, `a == b`, etc.
///   * `AssignmentExpressionNode` (M8.3) — `a = b`, `a += b`.
///   * `ConditionalExpressionNode` (M8.3) — `cond ? then : else`.
///   * `AwaitExpressionNode` (M8.3) — `await expr`.
///   * `PrefixExpressionNode` (M8.3) — `!x`, `-x`, `++x`.
///   * `PostfixExpressionNode` (M8.3) — `x++`, `x--`.
///   * `PropertyAccessExpressionNode` (M8.3) — `target.property`
///     (without invocation parens).
///   * `OpaqueExpressionNode` — catch-all for cascade, index,
///     instance creation, list/set/map/record literals, string
///     interpolation, function expressions, throw-expressions, cast,
///     is, etc.
///
/// Every subtype ends in `*ExpressionNode` for consistency with the
/// rest of the kernel's sealed-hierarchy naming and to avoid clashing
/// with analyzer types of the same root name (e.g. analyzer's
/// `BinaryExpression`, `AssignmentExpression`, etc.).
sealed class ExpressionNode {
  const ExpressionNode();

  /// Span of the full expression in the source.
  SourceSpan get sourceSpan;
}

/// A simple identifier reference — `x`, `print`, `myVar`. A property
/// access like `foo.bar` is `PropertyAccessExpressionNode`, not this.
class IdentifierExpressionNode extends ExpressionNode {
  const IdentifierExpressionNode({
    required this.name,
    required this.sourceSpan,
  });

  final String name;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() => 'IdentifierExpressionNode($name)';
}

/// A literal value — int, double, string, boolean, null. The literal's
/// raw source is preserved verbatim (e.g. `0xFF`, `1_000_000`,
/// `'it\'s'`, `"""triple"""`) — the kernel doesn't normalize literal
/// representations.
class LiteralExpressionNode extends ExpressionNode {
  const LiteralExpressionNode({
    required this.kind,
    required this.source,
    required this.sourceSpan,
  });

  final LiteralKind kind;
  final String source;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() => 'LiteralExpressionNode(${kind.name}: $source)';
}

/// Kinds of `LiteralExpressionNode`. String literals INCLUDE adjacent-
/// concatenation forms (`'a' 'b'`) — they're a single string literal
/// in the analyzer AST.
enum LiteralKind {
  intLiteral,
  doubleLiteral,
  stringLiteral,
  boolLiteral,
  nullLiteral,
}

/// A method invocation — `print(x)`, `x.method(y)`, `Foo.bar(z)`.
///
/// `target` is null for top-level invocations (`print(x)`). For
/// `x.method(y)`, target is `IdentifierExpressionNode(x)` and
/// methodName is `method`. The arguments list is captured as raw
/// source (`(x, y)`) including the surrounding parens — modeling
/// individual arguments structurally is deferred.
class MethodInvocationExpressionNode extends ExpressionNode {
  const MethodInvocationExpressionNode({
    required this.target,
    required this.dotSpan,
    required this.methodName,
    required this.methodNameSpan,
    required this.argumentsSource,
    required this.argumentsSpan,
    required this.sourceSpan,
  });

  /// The target expression (e.g. `x` in `x.method(y)`), or null when
  /// this is a top-level invocation (`f(args)`).
  final ExpressionNode? target;

  /// Span of the `.` separator. Null when [target] is null.
  final SourceSpan? dotSpan;

  /// The invoked method's name.
  final String methodName;
  final SourceSpan methodNameSpan;

  /// Raw source of the argument list INCLUDING the surrounding parens.
  final String argumentsSource;
  final SourceSpan argumentsSpan;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() => target == null
      ? 'MethodInvocationExpressionNode($methodName$argumentsSource)'
      : 'MethodInvocationExpressionNode'
          '($target.$methodName$argumentsSource)';
}

/// A binary expression — `a + b`, `a == b`, `a && b`, `a ?? b`, etc.
///
/// Named with the `Node` suffix to avoid clashing with the analyzer's
/// `BinaryExpression` type (other expression kinds don't clash, but
/// this one does).
///
/// Operands are recursive — they're full `ExpressionNode`s, so
/// `a + b * c` produces `BinaryExpressionNode(a, +, BinaryExpressionNode(b, *, c))`
/// matching the analyzer's precedence parsing. Editing the operator
/// or operands works the same regardless of nesting depth.
class BinaryExpressionNode extends ExpressionNode {
  const BinaryExpressionNode({
    required this.leftOperand,
    required this.operator,
    required this.operatorSpan,
    required this.rightOperand,
    required this.sourceSpan,
  });

  final ExpressionNode leftOperand;

  /// The operator token's lexeme — `+`, `-`, `*`, `/`, `~/`, `%`,
  /// `==`, `!=`, `<`, `<=`, `>`, `>=`, `&&`, `||`, `??`, `|`, `&`,
  /// `^`, `<<`, `>>`, `>>>`, `as`, `is`.
  final String operator;
  final SourceSpan operatorSpan;

  final ExpressionNode rightOperand;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() =>
      'BinaryExpressionNode($leftOperand $operator $rightOperand)';
}

/// An assignment expression — `a = b`, `a += b`, `a ??= b`, etc.
/// Both sides are recursive `ExpressionNode`s.
class AssignmentExpressionNode extends ExpressionNode {
  const AssignmentExpressionNode({
    required this.leftHandSide,
    required this.operator,
    required this.operatorSpan,
    required this.rightHandSide,
    required this.sourceSpan,
  });

  final ExpressionNode leftHandSide;

  /// The operator lexeme: `=`, `+=`, `-=`, `*=`, `/=`, `~/=`, `%=`,
  /// `&=`, `|=`, `^=`, `<<=`, `>>=`, `>>>=`, `??=`.
  final String operator;
  final SourceSpan operatorSpan;

  final ExpressionNode rightHandSide;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() =>
      'AssignmentExpressionNode($leftHandSide $operator $rightHandSide)';
}

/// A conditional (ternary) expression — `cond ? then : else`.
class ConditionalExpressionNode extends ExpressionNode {
  const ConditionalExpressionNode({
    required this.condition,
    required this.questionSpan,
    required this.thenExpression,
    required this.colonSpan,
    required this.elseExpression,
    required this.sourceSpan,
  });

  final ExpressionNode condition;
  final SourceSpan questionSpan;
  final ExpressionNode thenExpression;
  final SourceSpan colonSpan;
  final ExpressionNode elseExpression;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() => 'ConditionalExpressionNode('
      '$condition ? $thenExpression : $elseExpression)';
}

/// An `await expr` expression. Only valid inside `async` / `async*`
/// function bodies.
class AwaitExpressionNode extends ExpressionNode {
  const AwaitExpressionNode({
    required this.awaitKeywordSpan,
    required this.expression,
    required this.sourceSpan,
  });

  final SourceSpan awaitKeywordSpan;
  final ExpressionNode expression;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() => 'AwaitExpressionNode(await $expression)';
}

/// A prefix expression — `!x`, `-x`, `~x`, `++x`, `--x`. The operator
/// is captured as its lexeme; the operand is recursive.
class PrefixExpressionNode extends ExpressionNode {
  const PrefixExpressionNode({
    required this.operator,
    required this.operatorSpan,
    required this.operand,
    required this.sourceSpan,
  });

  /// The operator lexeme: `!`, `-`, `~`, `++`, `--`.
  final String operator;
  final SourceSpan operatorSpan;
  final ExpressionNode operand;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() => 'PrefixExpressionNode($operator$operand)';
}

/// A postfix expression — `x++`, `x--`. Less common forms than prefix.
class PostfixExpressionNode extends ExpressionNode {
  const PostfixExpressionNode({
    required this.operand,
    required this.operator,
    required this.operatorSpan,
    required this.sourceSpan,
  });

  final ExpressionNode operand;

  /// The operator lexeme: `++`, `--`, `!` (null-assert postfix).
  final String operator;
  final SourceSpan operatorSpan;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() => 'PostfixExpressionNode($operand$operator)';
}

/// A property access — `x.y`, `foo?.bar`. Does NOT include the
/// invocation parens — `x.y(z)` is a `MethodInvocationExpressionNode`,
/// not this.
class PropertyAccessExpressionNode extends ExpressionNode {
  const PropertyAccessExpressionNode({
    required this.target,
    required this.operator,
    required this.operatorSpan,
    required this.propertyName,
    required this.propertyNameSpan,
    required this.sourceSpan,
  });

  /// The target expression. May be null in rare cascade-property
  /// contexts (`..y` in a cascade).
  final ExpressionNode? target;

  /// The operator lexeme: `.`, `?.`, or `..` (cascade prop access).
  final String operator;
  final SourceSpan operatorSpan;

  final String propertyName;
  final SourceSpan propertyNameSpan;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() => target == null
      ? 'PropertyAccessExpressionNode($operator$propertyName)'
      : 'PropertyAccessExpressionNode($target$operator$propertyName)';
}

/// A prefixed identifier — `prefix.name`, where `prefix` is a simple
/// identifier. The analyzer uses this shape (not `PropertyAccess`)
/// when the target is a bare identifier — e.g. `Math.pi`, `lib.foo`,
/// `myObj.field`. Common.
class PrefixedIdentifierExpressionNode extends ExpressionNode {
  const PrefixedIdentifierExpressionNode({
    required this.prefix,
    required this.prefixSpan,
    required this.periodSpan,
    required this.identifier,
    required this.identifierSpan,
    required this.sourceSpan,
  });

  /// The prefix identifier (e.g. `lib` in `lib.foo`).
  final String prefix;
  final SourceSpan prefixSpan;

  /// Span of the `.` separator.
  final SourceSpan periodSpan;

  /// The identifier after the prefix (e.g. `foo` in `lib.foo`).
  final String identifier;
  final SourceSpan identifierSpan;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() => 'PrefixedIdentifierExpressionNode($prefix.$identifier)';
}

/// An index expression — `a[b]`, `map['key']`, `nullable?[k]`. The
/// target and index are recursive expressions.
class IndexExpressionExpressionNode extends ExpressionNode {
  const IndexExpressionExpressionNode({
    required this.target,
    required this.questionSpan,
    required this.leftBracketSpan,
    required this.index,
    required this.rightBracketSpan,
    required this.sourceSpan,
  });

  /// The indexed target. May be null in rare cascade contexts.
  final ExpressionNode? target;

  /// Span of the `?` for null-aware index (`a?[b]`); null otherwise.
  final SourceSpan? questionSpan;

  final SourceSpan leftBracketSpan;
  final ExpressionNode index;
  final SourceSpan rightBracketSpan;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() => target == null
      ? 'IndexExpressionExpressionNode([$index])'
      : 'IndexExpressionExpressionNode($target[$index])';
}

/// An instance creation — `Foo(args)`, `const Foo()`, `new Foo()`,
/// `Foo.named(args)`, `prefix.Foo<T>.named(args)`. Captures the
/// optional `const`/`new` keyword, the constructor name (raw source —
/// includes prefix, type args, and named-ctor segment), and the
/// argument list (raw source including parens).
class InstanceCreationExpressionNode extends ExpressionNode {
  const InstanceCreationExpressionNode({
    required this.keywordSpan,
    required this.constructorNameSource,
    required this.constructorNameSpan,
    required this.argumentsSource,
    required this.argumentsSpan,
    required this.sourceSpan,
  });

  /// Span of the leading `const` or `new` keyword when present.
  final SourceSpan? keywordSpan;

  /// Raw source of the constructor name (e.g. `Foo`, `Foo<int>`,
  /// `prefix.Foo.named`, `Result<int>.success`).
  final String constructorNameSource;
  final SourceSpan constructorNameSpan;

  /// Raw source of the argument list including the surrounding parens.
  final String argumentsSource;
  final SourceSpan argumentsSpan;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() =>
      'InstanceCreationExpressionNode($constructorNameSource$argumentsSource)';
}

/// An `as` cast expression — `x as int`, `value as MyType`.
class AsExpressionNode extends ExpressionNode {
  const AsExpressionNode({
    required this.expression,
    required this.asKeywordSpan,
    required this.typeSource,
    required this.typeSpan,
    required this.sourceSpan,
  });

  final ExpressionNode expression;
  final SourceSpan asKeywordSpan;

  /// Raw source of the type (e.g. `int`, `List<String>`).
  final String typeSource;
  final SourceSpan typeSpan;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() => 'AsExpressionNode($expression as $typeSource)';
}

/// An `is` type-check expression — `x is int`, `x is! String`. The
/// optional `!` operator (`is!`) negates the check.
class IsExpressionNode extends ExpressionNode {
  const IsExpressionNode({
    required this.expression,
    required this.isKeywordSpan,
    required this.notKeywordSpan,
    required this.typeSource,
    required this.typeSpan,
    required this.sourceSpan,
  });

  final ExpressionNode expression;
  final SourceSpan isKeywordSpan;

  /// Span of the `!` in `is!` form; null for plain `is`.
  final SourceSpan? notKeywordSpan;

  final String typeSource;
  final SourceSpan typeSpan;

  @override
  final SourceSpan sourceSpan;

  /// True when this is `is!` (negated check).
  bool get isNegated => notKeywordSpan != null;

  @override
  String toString() =>
      'IsExpressionNode($expression is${isNegated ? '!' : ''} $typeSource)';
}

/// An expression kind not yet modeled. Preserves the raw source.
/// Future milestones can promote individual kinds.
class OpaqueExpressionNode extends ExpressionNode {
  const OpaqueExpressionNode({
    required this.sourceText,
    required this.sourceSpan,
  });

  final String sourceText;

  @override
  final SourceSpan sourceSpan;

  @override
  String toString() {
    final preview = sourceText.length > 40
        ? '${sourceText.substring(0, 40).replaceAll('\n', '\\n')}...'
        : sourceText.replaceAll('\n', '\\n');
    return 'OpaqueExpressionNode("$preview")';
  }
}
