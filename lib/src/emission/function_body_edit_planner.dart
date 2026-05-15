import '../model/function_body.dart';
import 'source_edit.dart';

/// Plans `SourceEdit`s for individual function-body changes (M8.0a/b).
///
/// Statement-list operations (work on any `StatementBlock` — function
/// body OR nested if-then/if-else blocks):
///   * `addStatement` — insert a new statement at a given index.
///   * `removeStatement` — delete a statement + trailing whitespace.
///   * `replaceStatement` — replace a whole statement's source.
///
/// Variable-declaration operations:
///   * `renameDeclaredVariable` — change a variable's name token.
///   * `changeVariableType` — replace a declaration's type annotation.
///   * `changeVariableInitializer` — replace a variable's `= expr`
///     portion (requires existing initializer).
///
/// Return-statement operations:
///   * `changeReturnExpression` — replace the returned expression
///     (requires existing expression; bare `return;` adds need a
///     separate operation, deferred).
///
/// If-statement operations (M8.0b/c):
///   * `changeIfCondition` — replace the condition expression of any
///     `IfStatementNode` (including the head of an else-if chain or any
///     inner branch via `IfStatementNode.elseIf`).
///   * Then/else/else-if block edits work via the `StatementBlock`-
///     taking ops above (`addStatement`, `removeStatement`, etc.).
///
/// Loop operations (M8.0c/d):
///   * `changeWhileCondition` — replace the condition expression of a
///     `WhileStatementNode`.
///   * `changeDoWhileCondition` — replace the condition of a
///     `DoStatementNode`.
///   * `ForStatementNode.headerSource` is currently opaque (the parser
///     captures the parenthesized header as raw text), so dedicated
///     header-editing ops are deferred until a node-level model exists.
///   * Loop body edits use the statement-list ops with the loop's
///     `body` block.
///
/// Try/throw operations (M8.0d):
///   * `changeThrownExpression` — replace the expression of a
///     `ThrowStatementNode`.
///   * Try-block, catch-clause body, and finally-block edits all reuse
///     the `StatementBlock`-taking statement-list ops above.
///
/// Switch operations (M8.0e):
///   * `changeSwitchExpression` — replace the value being switched on.
///   * `changeSwitchCasePattern` — replace the pattern of a single case
///     (works on both legacy `case expr:` and Dart 3 `case pattern:`).
///   * `changeSwitchCaseGuard` — replace the `when ...` guard of a
///     pattern case (requires an existing guard).
///   * Case/default body edits reuse the `StatementBlock`-taking ops
///     above. Switch-case bodies are brace-less (`StatementBlock`'s
///     `hasBraces` is false); `addStatement` handles that path.
///
/// Pattern-internal operations (M8.0f):
///   * `renameDeclaredPatternVariable` — rename the bound variable of
///     a `DeclaredVariablePatternNode` (e.g. `case int n:` → `case
///     int value:`).
///   * `changeDeclaredPatternType` — change the type annotation of a
///     declared variable pattern (requires existing type).
///   * `changeConstantPatternExpression` — replace the constant
///     expression of a `ConstantPatternNode`.
///
/// Deliberately deferred (M8.1+):
///   * Bare-statement control-flow bodies (`if (cond) doIt();`,
///     `for (x in xs) f(x);`) — opaqued.
///   * Other control flow: yield, break, continue, labeled statements.
///   * Modeling the c-style/for-each structure inside
///     `ForStatementNode.headerSource`.
///   * Modeling switch case patterns (constant / type-test / object /
///     record / list / map / `||` alternatives) — currently opaque.
///   * Adding a `when` guard to a guard-less case (requires inserting
///     the `when` keyword).
///   * Adding/removing/reordering catch clauses on a try statement, or
///     switch cases on a switch statement.
///   * Switch **expressions** (the `=>`-based form) — they're
///     expressions, not statements; stay opaque inside the host.
///   * Editing inside `ExpressionStatement.expressionSource` —
///     requires modeling expression structure.
///   * Adding type annotation to an untyped variable declaration.
///   * Adding/removing variable qualifiers (final/var/late/const).
///   * Reordering statements (use add + remove for now).
class FunctionBodyEditPlanner {
  FunctionBodyEditPlanner._();

  // ----------------------- Statement-list ops ---------------------

  /// Inserts `newStatementSource` (e.g. `'print(x);'`) at position
  /// `index` in the given block's statement list. Indices in
  /// `[0, block.statements.length]` are valid; `block.statements.length`
  /// appends.
  ///
  /// `block` can be a function body's top-level block OR any nested
  /// block (e.g. the then/else block of an `IfStatementNode`). The
  /// operation works recursively without special-casing.
  ///
  /// Indentation is inferred from an existing statement (if any),
  /// otherwise derived from the block's brace position.
  static SourceEdit addStatement({
    required StatementBlock block,
    required int index,
    required String newStatementSource,
    required String source,
  }) {
    if (index < 0 || index > block.statements.length) {
      throw ArgumentError(
        'Insert index $index out of range [0, ${block.statements.length}]',
      );
    }

    // Empty block. Two flavors: braced (`{}` → `{\n  newStmt;\n}`) and
    // brace-less (switch-case bodies — insert after the `:` without a
    // re-emitted closing brace).
    if (block.statements.isEmpty) {
      if (!block.hasBraces) {
        // Brace-less: peek BACKWARDS to find the line the case
        // keyword starts on, indent from there + one level.
        final caseIndent = _lineIndentBefore(block.blockSpan.offset, source);
        final innerIndent = '$caseIndent  ';
        return SourceEdit(
          offset: block.innerSpan.offset,
          length: 0,
          replacement: '\n$innerIndent$newStatementSource',
        );
      }
      final outerIndent = _lineIndentBefore(block.blockSpan.offset, source);
      final innerIndent = '$outerIndent  ';
      return SourceEdit(
        offset: block.innerSpan.offset,
        length: block.innerSpan.length,
        replacement: '\n$innerIndent$newStatementSource\n$outerIndent',
      );
    }

    if (index < block.statements.length) {
      // Insert before the existing statement at `index`.
      final next = block.statements[index];
      final indent = _lineIndentBefore(next.sourceSpan.offset, source);
      return SourceEdit(
        offset: next.sourceSpan.offset,
        length: 0,
        replacement: '$newStatementSource\n$indent',
      );
    }
    // Append after the last statement.
    final last = block.statements.last;
    final indent = _lineIndentBefore(last.sourceSpan.offset, source);
    return SourceEdit(
      offset: last.sourceSpan.offset + last.sourceSpan.length,
      length: 0,
      replacement: '\n$indent$newStatementSource',
    );
  }

  /// Removes a statement entirely, including trailing whitespace up to
  /// and including the next newline. Same line-collapse pattern as
  /// M7's `removeMember`.
  static SourceEdit removeStatement({
    required StatementNode statement,
    required String source,
  }) {
    final start = statement.sourceSpan.offset;
    var end = statement.sourceSpan.offset + statement.sourceSpan.length;
    while (end < source.length) {
      final ch = source.codeUnitAt(end);
      if (ch == 0x20 || ch == 0x09 || ch == 0x0D) {
        end++;
      } else if (ch == 0x0A) {
        end++;
        break;
      } else {
        break;
      }
    }
    return SourceEdit(
      offset: start,
      length: end - start,
      replacement: '',
    );
  }

  /// Replaces a statement's full source text with `newStatementSource`.
  /// Useful for swapping `print(x);` → `log(x);` when the model doesn't
  /// surface internal structure of the expression.
  static SourceEdit replaceStatement({
    required StatementNode statement,
    required String newStatementSource,
  }) {
    return SourceEdit(
      offset: statement.sourceSpan.offset,
      length: statement.sourceSpan.length,
      replacement: newStatementSource,
    );
  }

  // ----------------------- Variable-declaration ops ---------------

  static SourceEdit renameDeclaredVariable({
    required DeclaredVariable variable,
    required String newName,
  }) =>
      SourceEdit(
        offset: variable.nameSpan.offset,
        length: variable.nameSpan.length,
        replacement: newName,
      );

  /// Replaces the type annotation of a declaration. The declaration
  /// must already have an explicit type; throws otherwise (adding a
  /// type to a `var`/`final`-without-type declaration is deferred).
  static SourceEdit changeVariableType({
    required VariableDeclarationStatementNode declaration,
    required String newType,
  }) {
    final span = declaration.typeSpan;
    if (span == null) {
      throw ArgumentError(
        'Variable declaration has no explicit type annotation; adding '
        'one is not supported in M8.0a.',
      );
    }
    return SourceEdit(
      offset: span.offset,
      length: span.length,
      replacement: newType,
    );
  }

  /// Replaces a variable's initializer expression with
  /// `newInitializerSource`. The variable must already have an
  /// initializer; throws otherwise.
  static SourceEdit changeVariableInitializer({
    required DeclaredVariable variable,
    required String newInitializerSource,
  }) {
    final span = variable.initializerSpan;
    if (span == null) {
      throw ArgumentError(
        'Variable "${variable.name}" has no initializer; adding one is '
        'not supported in M8.0a.',
      );
    }
    return SourceEdit(
      offset: span.offset,
      length: span.length,
      replacement: newInitializerSource,
    );
  }

  // ----------------------- If-statement ops (M8.0b) --------------

  /// Replaces the condition expression of an `if (cond) { ... }`
  /// statement with `newConditionSource`. The new source should NOT
  /// include the surrounding parentheses — they're preserved verbatim.
  ///
  /// For else-if chains (M8.0c), pass any branch's `IfStatementNode` —
  /// each branch has its own `conditionSpan`.
  static SourceEdit changeIfCondition({
    required IfStatementNode statement,
    required String newConditionSource,
  }) {
    return SourceEdit(
      offset: statement.conditionSpan.offset,
      length: statement.conditionSpan.length,
      replacement: newConditionSource,
    );
  }

  // ----------------------- While-statement ops (M8.0c) -----------

  /// Replaces the condition expression of a `while (cond) { ... }`
  /// statement with `newConditionSource`. The new source should NOT
  /// include the surrounding parentheses — they're preserved verbatim.
  static SourceEdit changeWhileCondition({
    required WhileStatementNode statement,
    required String newConditionSource,
  }) {
    return SourceEdit(
      offset: statement.conditionSpan.offset,
      length: statement.conditionSpan.length,
      replacement: newConditionSource,
    );
  }

  // ----------------------- Do-while ops (M8.0d) ------------------

  /// Replaces the trailing condition expression of a
  /// `do { ... } while (cond);` statement.
  static SourceEdit changeDoWhileCondition({
    required DoStatementNode statement,
    required String newConditionSource,
  }) {
    return SourceEdit(
      offset: statement.conditionSpan.offset,
      length: statement.conditionSpan.length,
      replacement: newConditionSource,
    );
  }

  // ----------------------- Switch-statement ops (M8.0e) ----------

  /// Replaces the expression of a `switch (expr) { ... }` statement
  /// with `newExpressionSource`. The new source should NOT include the
  /// surrounding parentheses — they're preserved verbatim.
  static SourceEdit changeSwitchExpression({
    required SwitchStatementNode statement,
    required String newExpressionSource,
  }) {
    return SourceEdit(
      offset: statement.expressionSpan.offset,
      length: statement.expressionSpan.length,
      replacement: newExpressionSource,
    );
  }

  /// Replaces the pattern of a single `case` clause with
  /// `newPatternSource`. Works on both legacy `case expr:` and Dart 3
  /// `case pattern [when guard]:` shapes.
  ///
  /// The new source replaces only the pattern; any `when` guard is
  /// preserved separately.
  static SourceEdit changeSwitchCasePattern({
    required SwitchCaseNode caseMember,
    required String newPatternSource,
  }) {
    return SourceEdit(
      offset: caseMember.patternSpan.offset,
      length: caseMember.patternSpan.length,
      replacement: newPatternSource,
    );
  }

  /// Replaces the `when` guard expression of a pattern case with
  /// `newGuardSource`. The case must already have a `when` guard;
  /// throws otherwise (adding a guard to a guard-less case is
  /// deferred — it would require inserting the `when` keyword).
  static SourceEdit changeSwitchCaseGuard({
    required SwitchCaseNode caseMember,
    required String newGuardSource,
  }) {
    final span = caseMember.whenGuardSpan;
    if (span == null) {
      throw ArgumentError(
        'Switch case has no `when` guard to replace. Adding a guard '
        'to a guard-less case is not yet supported.',
      );
    }
    return SourceEdit(
      offset: span.offset,
      length: span.length,
      replacement: newGuardSource,
    );
  }

  // ----------------------- Pattern-internal ops (M8.0f) ----------

  /// Renames the bound variable of a `DeclaredVariablePatternNode` —
  /// e.g. `case int n:` → `case int value:`. Replaces just the name
  /// token; type and qualifier (if any) are preserved.
  ///
  /// Note: the new name appears ONLY in the pattern itself. References
  /// to the old name in the `when` guard or case body are NOT updated
  /// here — those edits live at the call site (the kernel models source
  /// spans, not a symbol table).
  static SourceEdit renameDeclaredPatternVariable({
    required DeclaredVariablePatternNode pattern,
    required String newName,
  }) {
    return SourceEdit(
      offset: pattern.nameSpan.offset,
      length: pattern.nameSpan.length,
      replacement: newName,
    );
  }

  /// Changes the type annotation of a `DeclaredVariablePatternNode` —
  /// e.g. `case int n:` → `case double n:`. The pattern must already
  /// have an explicit type annotation; throws otherwise (adding a type
  /// to a `case var x:` is deferred).
  static SourceEdit changeDeclaredPatternType({
    required DeclaredVariablePatternNode pattern,
    required String newType,
  }) {
    final span = pattern.typeSpan;
    if (span == null) {
      throw ArgumentError(
        'Declared variable pattern has no explicit type to replace. '
        'Adding a type to a `var`/`final` pattern is not yet supported.',
      );
    }
    return SourceEdit(
      offset: span.offset,
      length: span.length,
      replacement: newType,
    );
  }

  /// Replaces the constant expression of a `ConstantPatternNode` —
  /// e.g. `case 0:` → `case 42:`, `case 'foo':` → `case 'bar':`.
  /// Preserves the optional leading `const` keyword (when present).
  static SourceEdit changeConstantPatternExpression({
    required ConstantPatternNode pattern,
    required String newExpressionSource,
  }) {
    return SourceEdit(
      offset: pattern.expressionSpan.offset,
      length: pattern.expressionSpan.length,
      replacement: newExpressionSource,
    );
  }

  // ----------------------- Throw-statement ops (M8.0d) -----------

  /// Replaces the expression of a `throw expr;` statement.
  static SourceEdit changeThrownExpression({
    required ThrowStatementNode statement,
    required String newExpressionSource,
  }) {
    return SourceEdit(
      offset: statement.expressionSpan.offset,
      length: statement.expressionSpan.length,
      replacement: newExpressionSource,
    );
  }

  // ----------------------- Return-statement ops -------------------

  /// Replaces the expression of a `return expr;` statement with
  /// `newExpressionSource`. The return statement must already have an
  /// expression; throws on bare `return;`.
  static SourceEdit changeReturnExpression({
    required ReturnStatementNode statement,
    required String newExpressionSource,
  }) {
    final span = statement.expressionSpan;
    if (span == null) {
      throw ArgumentError(
        'Return statement has no expression to replace. Use '
        'replaceStatement to convert `return;` into `return expr;`.',
      );
    }
    return SourceEdit(
      offset: span.offset,
      length: span.length,
      replacement: newExpressionSource,
    );
  }

  // ----------------------- Internal helpers -----------------------

  /// Returns the run of horizontal whitespace immediately preceding
  /// `offset` on its line. Duplicated from `ListEditHelpers` and
  /// `ClassStructureEditPlanner` — third user. Promote to a shared
  /// utility in the next cleanup pass.
  static String _lineIndentBefore(int offset, String source) {
    var lineStart = offset;
    while (lineStart > 0 && source.codeUnitAt(lineStart - 1) != 0x0A) {
      lineStart--;
    }
    var i = lineStart;
    while (i < offset) {
      final ch = source.codeUnitAt(i);
      if (ch == 0x20 || ch == 0x09) {
        i++;
      } else {
        break;
      }
    }
    return source.substring(lineStart, i);
  }
}
