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
/// class-only `isStatic` flag. Init expressions are raw source text.
class DeclaredVariable {
  const DeclaredVariable({
    required this.name,
    required this.nameSpan,
    required this.initializerSource,
    required this.initializerSpan,
  });

  final String name;
  final SourceSpan nameSpan;
  final String? initializerSource;
  final SourceSpan? initializerSpan;

  @override
  String toString() => 'DeclaredVariable($name'
      '${initializerSource == null ? '' : ' = $initializerSource'})';
}

/// A standalone expression used as a statement — `print(x);`,
/// `x = 5;`, `await fetch();`, `someInstance.method();`. The
/// expression's internal structure is NOT modeled in M8.0a; it lives
/// in `expressionSource` as raw text and round-trips verbatim.
class ExpressionStatementNode extends StatementNode {
  const ExpressionStatementNode({
    required this.expressionSource,
    required this.expressionSpan,
    required this.sourceSpan,
  });

  /// Raw source text of the expression (no trailing `;`).
  final String expressionSource;

  /// Span of just the expression (excludes the trailing `;`).
  final SourceSpan expressionSpan;

  /// Span of the full statement including the trailing `;`.
  @override
  final SourceSpan sourceSpan;

  @override
  String toString() {
    final preview = expressionSource.length > 40
        ? '${expressionSource.substring(0, 40).replaceAll('\n', '\\n')}...'
        : expressionSource.replaceAll('\n', '\\n');
    return 'ExpressionStatementNode("$preview")';
  }
}

/// A `return [expr];` statement. The expression is optional (bare
/// `return;` in `void` functions). Like `ExpressionStatement`, the
/// expression's internal structure is opaque.
class ReturnStatementNode extends StatementNode {
  const ReturnStatementNode({
    required this.expressionSource,
    required this.expressionSpan,
    required this.sourceSpan,
  });

  /// Returned expression as raw source, or null for bare `return;`.
  final String? expressionSource;
  final SourceSpan? expressionSpan;

  /// Span of the full statement including `return` and `;`.
  @override
  final SourceSpan sourceSpan;

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
/// forms — the entire parenthesized header is preserved as raw source.
/// Only fully-braced bodies are modeled; a bare-statement body
/// (`for (x in xs) f(x);`) falls through to `OpaqueStatementNode`.
///
/// **Why opaque header:** the header has three structurally different
/// shapes (init/cond/update triple, declared for-each, expression
/// for-each) plus optional `await` and pattern variants. Modeling them
/// requires three new node kinds — deferred until concrete fixtures
/// demand it. For now, edits to the body work via `StatementBlock`
/// without needing to understand the header.
class ForStatementNode extends StatementNode {
  const ForStatementNode({
    required this.forKeywordSpan,
    required this.awaitKeywordSpan,
    required this.headerSource,
    required this.headerSpan,
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
  final String headerSource;

  /// Span covering the parenthesized header.
  final SourceSpan headerSpan;

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
/// **Pattern surface (M8.0e scope):** every pattern is captured as
/// opaque source. Differentiating constant patterns, type-test patterns,
/// `||` alternatives, object/record/list/map patterns, and so on
/// requires a dozen new node kinds — deferred until concrete edits
/// demand it. Same opaque-source-for-now play as `ForStatementNode`'s
/// header.
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
  final String patternSource;
  final SourceSpan patternSpan;

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

/// A statement kind not yet modeled — `yield`, `break`, `continue`,
/// labeled statements, etc. (and `if`/`for`/`while`/`do`/`try`/`switch`
/// with bare-statement or otherwise unsupported shapes, which the M8.0e
/// parser punts on). Preserves the source verbatim through any edit to
/// surrounding statements; the kernel makes no guarantees about edits
/// that would target opaque content.
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
