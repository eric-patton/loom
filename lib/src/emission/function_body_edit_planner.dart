import 'package:analyzer/dart/analysis/utilities.dart';
// Hide analyzer's `PatternField` so the kernel-side `PatternField`
// (from function_body.dart) wins.
import 'package:analyzer/dart/ast/ast.dart' hide PatternField;
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../model/function_body.dart';
import 'source_edit.dart';

/// Plans `SourceEdit`s for individual function-body changes (M8.0a/b).
///
/// Statement-list operations (work on any `StatementBlock` — function
/// body OR nested if-then/if-else blocks):
///   * `addStatement` — insert a new statement at a given index.
///   * `removeStatement` — delete a statement + trailing whitespace.
///   * `replaceStatement` — replace a whole statement's source.
///   * `moveStatement` (M8.1) — reorder a statement within its block.
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
/// Object/record pattern operations (M8.0g):
///   * `changeObjectPatternType` — replace the class-type-name prefix
///     of an `ObjectPatternNode` (e.g. `case Point(x: 0):` →
///     `case Coord(x: 0):`).
///   * `renamePatternFieldName` — rename an explicit named field
///     (throws on positional/shorthand fields).
///   * `replacePatternFieldPattern` — replace a field's sub-pattern.
///     The recursive `PatternNode` shape means existing ops
///     (`changeConstantPatternExpression`, `renameDeclaredPatternVariable`,
///     etc.) also work on nested patterns inside object/record fields
///     without needing dedicated ops.
///
/// Remaining-pattern operations (M8.0h — closes pattern surface 14/14):
///   * `changeRelationalPatternOperator` / `changeRelationalPatternOperand`
///     — edit `case > 100:` style patterns.
///   * `changeCastPatternType` — edit the type in `case x as int:`.
///   * `changeMapPatternEntryKey` — edit the key in `{'name': v}`.
///   * No new ops needed for null-check / null-assert / parenthesized /
///     logical-and — edits propagate through the recursive inner-pattern
///     structure using existing ops.
///
/// Symbol-aware rename (M8.0h):
///   * `renameDeclaredPatternVariableWithReferences` — renames a pattern
///     variable AND all `SimpleIdentifier` references to it in the
///     case's `when` guard and body. Returns a list of `SourceEdit`s
///     suitable for `applySourceEdits`. Doesn't touch string literals
///     or comments. Caller-responsible for shadowing scenarios.
///
/// Yield/break/continue/label operations (M8.1):
///   * `changeYieldExpression` — replace yield's expression.
///   * `changeBreakLabel` / `changeContinueLabel` — replace the target
///     label of a labeled break/continue (throws on bare forms).
///   * `renameStatementLabel` — rename a `LabelNode` declaration on
///     a `LabeledStatementNode` (doesn't update break/continue refs).
///
/// For-loop header operations (M8.2):
///   * `changeCStyleForCondition` — replace the condition expression
///     of a c-style for header.
///   * `replaceCStyleForUpdater` — replace one updater by index.
///   * `renameForEachLoopVariable` — rename a for-each loop variable.
///   * `changeForEachLoopVariableType` — change its type (requires
///     existing type annotation).
///   * `changeForEachIterable` — replace the iterable expression.
///
/// Expression-internal operations (M8.2 first slice):
///   * `renameIdentifierExpression` — rename a simple identifier.
///   * `changeBinaryOperator` — swap the operator in a binary
///     expression.
///   * `changeMethodInvocationName` — rename the called method.
///   * `changeMethodInvocationArguments` — replace the argument list.
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

  /// Moves a statement from `fromIndex` to `toIndex` within `block`.
  ///
  /// `toIndex` is interpreted as the post-removal target index — same
  /// convention Dart's `List.insert` uses. So `moveStatement(0, 2)`
  /// in a 3-statement block produces the order `[1, 2, 0]`.
  ///
  /// Emits a single replace-range edit covering the source from the
  /// earlier-positioned statement's start to the later-positioned
  /// statement's end (inclusive of trailing newline), with the
  /// reordered content. This is byte-bounded — only the touched
  /// region is rewritten.
  ///
  /// Indentation of each moved statement is preserved verbatim. The
  /// edit does NOT reformat the block; if the original source had
  /// unusual whitespace patterns (e.g. blank lines between statements)
  /// they're carried through.
  static SourceEdit moveStatement({
    required StatementBlock block,
    required int fromIndex,
    required int toIndex,
    required String source,
  }) {
    if (fromIndex < 0 || fromIndex >= block.statements.length) {
      throw ArgumentError(
        'moveStatement fromIndex $fromIndex out of range '
        '[0, ${block.statements.length})',
      );
    }
    if (toIndex < 0 || toIndex >= block.statements.length) {
      throw ArgumentError(
        'moveStatement toIndex $toIndex out of range '
        '[0, ${block.statements.length})',
      );
    }
    if (fromIndex == toIndex) {
      // No-op move — return an empty-replace edit that doesn't change
      // anything. Using length: 0 + empty replacement at the statement's
      // start would also be a no-op; but returning a zero-effect edit
      // can trip applySourceEdits' same-offset checks if combined with
      // others, so we return a tautological edit instead.
      final stmt = block.statements[fromIndex];
      return SourceEdit(
        offset: stmt.sourceSpan.offset,
        length: stmt.sourceSpan.length,
        replacement: source.substring(
          stmt.sourceSpan.offset,
          stmt.sourceSpan.offset + stmt.sourceSpan.length,
        ),
      );
    }

    final earlier = fromIndex < toIndex ? fromIndex : toIndex;
    final later = fromIndex < toIndex ? toIndex : fromIndex;

    // Build the new in-block source by walking the statements in
    // their new order, joining them with the separators they
    // originally had (so trailing whitespace patterns are preserved).
    //
    // The affected range starts at the earlier statement's offset and
    // ends at the LATER statement's end-offset. We pull each
    // statement's verbatim source and the inter-statement filler
    // (whitespace/newlines/comments between them) and reorder.
    final regionStart = block.statements[earlier].sourceSpan.offset;
    final regionEnd = block.statements[later].sourceSpan.offset +
        block.statements[later].sourceSpan.length;

    // Build the new index ordering.
    final newOrder = <int>[];
    for (var i = 0; i < block.statements.length; i++) {
      newOrder.add(i);
    }
    final moved = newOrder.removeAt(fromIndex);
    newOrder.insert(toIndex, moved);

    // Walk only the [earlier, later] sub-range of newOrder (since the
    // edit covers only that region). The first statement in the
    // affected region keeps its position at regionStart; subsequent
    // statements join via inter-statement filler from the ORIGINAL
    // source between consecutive ORIGINAL statements.
    //
    // Strategy: walk the new order positions corresponding to indices
    // earlier..later, emit each statement's source. For separators
    // between them, use the original gap-text between adjacent
    // statements in the ORIGINAL block, scanned in source order.
    final originalGaps = <int, String>{};
    for (var i = earlier; i < later; i++) {
      final endOfCurrent = block.statements[i].sourceSpan.offset +
          block.statements[i].sourceSpan.length;
      final startOfNext = block.statements[i + 1].sourceSpan.offset;
      originalGaps[i] = source.substring(endOfCurrent, startOfNext);
    }

    // Map gap-index by source position: gap[i] separates statements
    // i and i+1 in the ORIGINAL ordering. When rebuilding, we use the
    // gap that originally sat AFTER the same SOURCE position — i.e.
    // we walk the new ordering but pick gaps by their original
    // position in the sequence. This preserves the visual spacing
    // pattern as much as possible: the first emitted statement's
    // trailing gap is gap[earlier], the second's is gap[earlier+1],
    // etc.
    final buf = StringBuffer();
    for (var pos = earlier; pos <= later; pos++) {
      final originalIndex = newOrder[pos];
      final stmt = block.statements[originalIndex];
      buf.write(source.substring(
        stmt.sourceSpan.offset,
        stmt.sourceSpan.offset + stmt.sourceSpan.length,
      ));
      if (pos < later) {
        // The gap between this output position and the next: use
        // the original gap that sat at position `pos` (i.e. between
        // original statements at indices `pos` and `pos+1`).
        buf.write(originalGaps[pos] ?? '\n');
      }
    }

    return SourceEdit(
      offset: regionStart,
      length: regionEnd - regionStart,
      replacement: buf.toString(),
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

  // ----------------------- Object/record pattern ops (M8.0g) -----

  /// Replaces the class-type-name prefix of an `ObjectPatternNode` —
  /// e.g. `case Point(x: 0):` → `case Coord(x: 0):`. The fields and
  /// their sub-patterns are preserved verbatim; only the type name
  /// changes.
  ///
  /// Works for parameterized types too — `case Result<int>(...)` →
  /// `case Result<num>(...)` replaces the full type name including
  /// type arguments.
  static SourceEdit changeObjectPatternType({
    required ObjectPatternNode pattern,
    required String newTypeNameSource,
  }) {
    return SourceEdit(
      offset: pattern.typeNameSpan.offset,
      length: pattern.typeNameSpan.length,
      replacement: newTypeNameSource,
    );
  }

  /// Renames the explicit field-name of a named field in an object or
  /// record pattern — e.g. `Point(x: 1, y: 2)` → `Point(left: 1, y: 2)`.
  ///
  /// Throws when the field is positional (no name) or shorthand (the
  /// name is implied by the inner pattern's variable). For shorthand
  /// fields, rename the inner variable via
  /// `renameDeclaredPatternVariable` — that propagates to the field
  /// name automatically.
  static SourceEdit renamePatternFieldName({
    required PatternField field,
    required String newName,
  }) {
    final span = field.fieldNameSpan;
    if (span == null) {
      throw ArgumentError(
        'Pattern field has no explicit name to rename. For positional '
        'fields there is no name; for shorthand `:varX` fields, rename '
        'the inner pattern variable instead — it acts as the field name.',
      );
    }
    return SourceEdit(
      offset: span.offset,
      length: span.length,
      replacement: newName,
    );
  }

  /// Replaces the entire sub-pattern of a field — e.g. swap
  /// `Point(x: 0, y: 0)` → `Point(x: int x, y: 0)` by replacing the
  /// first field's pattern (`0`) with `int x`.
  ///
  /// Sub-pattern types may differ between original and replacement
  /// (a constant pattern can become a declared variable pattern, etc.).
  /// The replacement source is interpreted as a complete pattern; it
  /// should not include the field's name prefix or surrounding colon.
  static SourceEdit replacePatternFieldPattern({
    required PatternField field,
    required String newPatternSource,
  }) {
    return SourceEdit(
      offset: field.pattern.sourceSpan.offset,
      length: field.pattern.sourceSpan.length,
      replacement: newPatternSource,
    );
  }

  // ----------------------- Remaining-pattern ops (M8.0h) ---------

  /// Changes the operator of a `RelationalPatternNode` — e.g.
  /// `case > 100:` → `case >= 100:`.
  static SourceEdit changeRelationalPatternOperator({
    required RelationalPatternNode pattern,
    required String newOperator,
  }) {
    return SourceEdit(
      offset: pattern.operatorSpan.offset,
      length: pattern.operatorSpan.length,
      replacement: newOperator,
    );
  }

  /// Changes the operand expression of a `RelationalPatternNode` —
  /// e.g. `case > 100:` → `case > 200:`.
  static SourceEdit changeRelationalPatternOperand({
    required RelationalPatternNode pattern,
    required String newOperandSource,
  }) {
    return SourceEdit(
      offset: pattern.operandSpan.offset,
      length: pattern.operandSpan.length,
      replacement: newOperandSource,
    );
  }

  /// Changes the type of a `CastPatternNode` — e.g. `case x as int:` →
  /// `case x as num:`.
  static SourceEdit changeCastPatternType({
    required CastPatternNode pattern,
    required String newTypeSource,
  }) {
    return SourceEdit(
      offset: pattern.typeSpan.offset,
      length: pattern.typeSpan.length,
      replacement: newTypeSource,
    );
  }

  /// Changes the key expression of a `MapPatternEntryNode` — e.g.
  /// `{'name': v}` → `{'username': v}`.
  static SourceEdit changeMapPatternEntryKey({
    required MapPatternEntryNode entry,
    required String newKeyExpressionSource,
  }) {
    return SourceEdit(
      offset: entry.keyExpressionSpan.offset,
      length: entry.keyExpressionSpan.length,
      replacement: newKeyExpressionSource,
    );
  }

  // ----------------------- Symbol-aware rename (M8.0h) -----------

  /// Renames the bound variable of a `DeclaredVariablePatternNode`
  /// AND updates all references to that variable within the case's
  /// `when` guard and body statements.
  ///
  /// The kernel re-parses the case region with the analyzer, walks
  /// the AST for `SimpleIdentifier` nodes matching `oldName`, and
  /// produces a `SourceEdit` for each. The returned list is in
  /// source order (sorted by offset) so that `applySourceEdits` can
  /// apply them without offset shifts.
  ///
  /// Unlike `renameDeclaredPatternVariable`, this op operates on the
  /// whole case scope. The `pattern` argument identifies which
  /// declared variable to rename; the `caseMember` argument is the
  /// enclosing case (needed to scope the search to its guard + body).
  ///
  /// Limitations:
  ///   * String literals containing the identifier text are NOT
  ///     edited (they're not identifier references).
  ///   * Comments containing the name are NOT edited.
  ///   * If the case body declares another local with the same name
  ///     (shadowing), this op renames the outer pattern variable but
  ///     leaves the inner shadow alone — actually wait, it WILL also
  ///     rename `n` references inside the shadow's scope, which is
  ///     wrong. The kernel doesn't track lexical scope; callers who
  ///     have shadowing should prefer the simpler
  ///     `renameDeclaredPatternVariable` and rewrite references
  ///     manually.
  static List<SourceEdit> renameDeclaredPatternVariableWithReferences({
    required SwitchCaseNode caseMember,
    required DeclaredVariablePatternNode pattern,
    required String newName,
    required String source,
  }) {
    final oldName = pattern.name;
    final edits = <SourceEdit>[];

    // 1. The pattern's name span itself.
    edits.add(SourceEdit(
      offset: pattern.nameSpan.offset,
      length: pattern.nameSpan.length,
      replacement: newName,
    ));

    // 2. Walk the guard expression (if any).
    final guardSpan = caseMember.whenGuardSpan;
    if (guardSpan != null) {
      _collectIdentifierEdits(
        source: source,
        regionOffset: guardSpan.offset,
        regionLength: guardSpan.length,
        oldName: oldName,
        newName: newName,
        out: edits,
      );
    }

    // 3. Walk each statement in the case body.
    for (final stmt in caseMember.body.statements) {
      _collectIdentifierEdits(
        source: source,
        regionOffset: stmt.sourceSpan.offset,
        regionLength: stmt.sourceSpan.length,
        oldName: oldName,
        newName: newName,
        out: edits,
      );
    }

    // Sort by offset so applySourceEdits can apply them cleanly.
    // The first edit (pattern name) is in front of the case region;
    // body/guard edits all come after. Sorting is just defensive.
    edits.sort((a, b) => a.offset.compareTo(b.offset));
    return edits;
  }

  /// Re-parses [source] (full file) and walks the subtree inside
  /// `[regionOffset, regionOffset + regionLength)` for `SimpleIdentifier`
  /// nodes whose `name` equals `oldName`. Adds a rename edit for each.
  static void _collectIdentifierEdits({
    required String source,
    required int regionOffset,
    required int regionLength,
    required String oldName,
    required String newName,
    required List<SourceEdit> out,
  }) {
    final result = parseString(content: source, throwIfDiagnostics: false);
    final visitor = _IdentifierCollector(
      regionStart: regionOffset,
      regionEnd: regionOffset + regionLength,
      target: oldName,
    );
    result.unit.accept(visitor);
    for (final id in visitor.matches) {
      out.add(SourceEdit(
        offset: id.offset,
        length: id.length,
        replacement: newName,
      ));
    }
  }

  // ----------------------- Symbol-aware rename — locals + labels (M8.9)

  /// Renames a local variable declared by a `VariableDeclarationStatementNode`
  /// AND updates all `SimpleIdentifier` references to it within the
  /// rest of the enclosing function body.
  ///
  /// Pass `functionBody` so the op knows the scope to search (everything
  /// from the variable's declaration to the end of the function body).
  /// Shadowing isn't tracked — if a nested block re-declares the same
  /// name, this op renames BOTH. Caller-responsible.
  ///
  /// Returns an offset-sorted list of edits.
  static List<SourceEdit> renameDeclaredVariableWithReferences({
    required DeclaredVariable variable,
    required FunctionBodyModel functionBody,
    required String newName,
    required String source,
  }) {
    final oldName = variable.name;
    final edits = <SourceEdit>[
      SourceEdit(
        offset: variable.nameSpan.offset,
        length: variable.nameSpan.length,
        replacement: newName,
      ),
    ];

    // Scope: from after the declaration to the end of the function body.
    final scopeStart = variable.nameSpan.offset + variable.nameSpan.length;
    final bodyEnd = functionBody.bodySpan.offset + functionBody.bodySpan.length;
    _collectIdentifierEdits(
      source: source,
      regionOffset: scopeStart,
      regionLength: bodyEnd - scopeStart,
      oldName: oldName,
      newName: newName,
      out: edits,
    );

    edits.sort((a, b) => a.offset.compareTo(b.offset));
    return edits;
  }

  /// Renames a for-each loop variable AND updates references within
  /// the loop body. Throws when the header is c-style (no loop variable).
  static List<SourceEdit> renameForEachLoopVariableWithReferences({
    required ForStatementNode forStatement,
    required String newName,
    required String source,
  }) {
    final header = forStatement.header;
    if (header is! ForEachHeader) {
      throw ArgumentError(
        'renameForEachLoopVariableWithReferences requires a ForEachHeader.',
      );
    }
    final oldName = header.loopVariableName;
    final edits = <SourceEdit>[
      SourceEdit(
        offset: header.loopVariableSpan.offset,
        length: header.loopVariableSpan.length,
        replacement: newName,
      ),
    ];

    _collectIdentifierEdits(
      source: source,
      regionOffset: forStatement.body.blockSpan.offset,
      regionLength: forStatement.body.blockSpan.length,
      oldName: oldName,
      newName: newName,
      out: edits,
    );

    edits.sort((a, b) => a.offset.compareTo(b.offset));
    return edits;
  }

  /// Renames a `LabelNode` declaration AND updates all
  /// `break label;` / `continue label;` references within the labeled
  /// statement's body.
  ///
  /// Walks the AST for `BreakStatement` / `ContinueStatement` nodes
  /// whose label matches; produces a rename edit for each match plus
  /// the label declaration itself.
  static List<SourceEdit> renameStatementLabelWithReferences({
    required LabeledStatementNode labeledStatement,
    required LabelNode label,
    required String newName,
    required String source,
  }) {
    final oldName = label.name;
    final edits = <SourceEdit>[
      SourceEdit(
        offset: label.nameSpan.offset,
        length: label.nameSpan.length,
        replacement: newName,
      ),
    ];

    final regionStart = labeledStatement.statement.sourceSpan.offset;
    final regionEnd = labeledStatement.statement.sourceSpan.offset +
        labeledStatement.statement.sourceSpan.length;

    final result = parseString(content: source, throwIfDiagnostics: false);
    final visitor = _LabelReferenceCollector(
      regionStart: regionStart,
      regionEnd: regionEnd,
      target: oldName,
    );
    result.unit.accept(visitor);
    for (final ref in visitor.matches) {
      edits.add(SourceEdit(
        offset: ref.offset,
        length: ref.length,
        replacement: newName,
      ));
    }

    edits.sort((a, b) => a.offset.compareTo(b.offset));
    return edits;
  }

  // ----------------------- For-header ops (M8.2) -----------------

  /// Replaces the condition expression of a c-style for-loop header.
  /// Throws when the header is a `ForEachHeader` or `OpaqueForLoopHeader`,
  /// or when the c-style header has no condition (`for (i = 0; ; i++)`).
  static SourceEdit changeCStyleForCondition({
    required ForLoopHeader header,
    required String newConditionSource,
  }) {
    if (header is! CStyleForHeader) {
      throw ArgumentError(
        'changeCStyleForCondition only applies to CStyleForHeader; '
        'got ${header.runtimeType}.',
      );
    }
    final span = header.conditionSpan;
    if (span == null) {
      throw ArgumentError(
        'C-style for-header has no condition expression to replace. '
        'Adding one (to `for (init; ; updaters)`) is deferred.',
      );
    }
    return SourceEdit(
      offset: span.offset,
      length: span.length,
      replacement: newConditionSource,
    );
  }

  /// Replaces a single updater in a c-style for-header by index.
  /// `for (var i = 0; cond; i++, j *= 2)` has two updaters; passing
  /// `updaterIndex: 1` rewrites `j *= 2`.
  static SourceEdit replaceCStyleForUpdater({
    required ForLoopHeader header,
    required int updaterIndex,
    required String newUpdaterSource,
  }) {
    if (header is! CStyleForHeader) {
      throw ArgumentError(
        'replaceCStyleForUpdater only applies to CStyleForHeader; '
        'got ${header.runtimeType}.',
      );
    }
    if (updaterIndex < 0 || updaterIndex >= header.updaterSpans.length) {
      throw ArgumentError(
        'updaterIndex $updaterIndex out of range '
        '[0, ${header.updaterSpans.length})',
      );
    }
    final span = header.updaterSpans[updaterIndex];
    return SourceEdit(
      offset: span.offset,
      length: span.length,
      replacement: newUpdaterSource,
    );
  }

  /// Renames a `ForEachHeader`'s loop variable. Works for both
  /// declared (`for (var x in iter)`) and existing-identifier
  /// (`for (x in iter)`) shapes. Does NOT update references to the
  /// variable inside the loop body — caller-responsible (or future
  /// symbol-aware op).
  static SourceEdit renameForEachLoopVariable({
    required ForLoopHeader header,
    required String newName,
  }) {
    if (header is! ForEachHeader) {
      throw ArgumentError(
        'renameForEachLoopVariable only applies to ForEachHeader; '
        'got ${header.runtimeType}.',
      );
    }
    return SourceEdit(
      offset: header.loopVariableSpan.offset,
      length: header.loopVariableSpan.length,
      replacement: newName,
    );
  }

  /// Changes the type annotation of a `ForEachHeader`'s declared loop
  /// variable. Throws when the header has no type annotation
  /// (e.g. `for (var x in iter)` has no explicit type).
  static SourceEdit changeForEachLoopVariableType({
    required ForLoopHeader header,
    required String newType,
  }) {
    if (header is! ForEachHeader) {
      throw ArgumentError(
        'changeForEachLoopVariableType only applies to ForEachHeader; '
        'got ${header.runtimeType}.',
      );
    }
    final span = header.typeSpan;
    if (span == null) {
      throw ArgumentError(
        'For-each header has no explicit type annotation to replace.',
      );
    }
    return SourceEdit(
      offset: span.offset,
      length: span.length,
      replacement: newType,
    );
  }

  /// Replaces the iterable expression of a `ForEachHeader` — e.g.
  /// `for (var x in users)` → `for (var x in activeUsers)`.
  static SourceEdit changeForEachIterable({
    required ForLoopHeader header,
    required String newIterableSource,
  }) {
    if (header is! ForEachHeader) {
      throw ArgumentError(
        'changeForEachIterable only applies to ForEachHeader; '
        'got ${header.runtimeType}.',
      );
    }
    return SourceEdit(
      offset: header.iterableSpan.offset,
      length: header.iterableSpan.length,
      replacement: newIterableSource,
    );
  }

  // ----------------------- Expression ops (M8.2) -----------------

  /// Renames a simple `IdentifierExpressionNode` — e.g. `x` → `value`.
  /// Use `renameDeclaredPatternVariableWithReferences` (M8.0h) for
  /// the symbol-aware variant inside switch cases.
  static SourceEdit renameIdentifierExpression({
    required IdentifierExpressionNode expression,
    required String newName,
  }) {
    return SourceEdit(
      offset: expression.sourceSpan.offset,
      length: expression.sourceSpan.length,
      replacement: newName,
    );
  }

  /// Changes the operator of a `BinaryExpressionNode` — e.g.
  /// `a + b` → `a - b`. Operator must be valid Dart (`+`, `-`, `*`,
  /// `==`, `&&`, etc.) — the kernel doesn't validate; if you pass
  /// nonsense the source will fail to re-parse.
  static SourceEdit changeBinaryOperator({
    required BinaryExpressionNode expression,
    required String newOperator,
  }) {
    return SourceEdit(
      offset: expression.operatorSpan.offset,
      length: expression.operatorSpan.length,
      replacement: newOperator,
    );
  }

  /// Renames the called method on a `MethodInvocationExpressionNode` —
  /// e.g. `print(x)` → `log(x)`, `x.foo(y)` → `x.bar(y)`. The target
  /// (if any) and arguments are preserved verbatim.
  static SourceEdit changeMethodInvocationName({
    required MethodInvocationExpressionNode expression,
    required String newMethodName,
  }) {
    return SourceEdit(
      offset: expression.methodNameSpan.offset,
      length: expression.methodNameSpan.length,
      replacement: newMethodName,
    );
  }

  /// Replaces the argument list of a `MethodInvocationExpressionNode` —
  /// e.g. `print(x)` → `print(x, y)`. The new source MUST include
  /// the surrounding parens.
  static SourceEdit changeMethodInvocationArguments({
    required MethodInvocationExpressionNode expression,
    required String newArgumentsSource,
  }) {
    return SourceEdit(
      offset: expression.argumentsSpan.offset,
      length: expression.argumentsSpan.length,
      replacement: newArgumentsSource,
    );
  }

  /// Renames a `NamedArgumentNode`'s name — e.g. `f(name: x)` →
  /// `f(label: x)`. The colon and argument expression are preserved.
  static SourceEdit renameNamedArgument({
    required NamedArgumentNode argument,
    required String newName,
  }) {
    return SourceEdit(
      offset: argument.nameSpan.offset,
      length: argument.nameSpan.length,
      replacement: newName,
    );
  }

  /// Replaces an argument's expression — works for both positional
  /// and named arguments. The argument's name (if named) is preserved.
  static SourceEdit replaceArgumentExpression({
    required ArgumentNode argument,
    required String newExpressionSource,
  }) {
    final span = argument.expression.sourceSpan;
    return SourceEdit(
      offset: span.offset,
      length: span.length,
      replacement: newExpressionSource,
    );
  }

  // ----------------------- Expression ops (M8.3) -----------------

  /// Changes the operator of an `AssignmentExpressionNode` — e.g.
  /// `a = b` → `a += b`. Operator must be a valid Dart assignment
  /// operator (`=`, `+=`, `-=`, `*=`, `??=`, etc.).
  static SourceEdit changeAssignmentOperator({
    required AssignmentExpressionNode expression,
    required String newOperator,
  }) {
    return SourceEdit(
      offset: expression.operatorSpan.offset,
      length: expression.operatorSpan.length,
      replacement: newOperator,
    );
  }

  /// Changes the operator of a `PrefixExpressionNode` — e.g.
  /// `!x` → `-x`. Operator must be a valid Dart prefix operator
  /// (`!`, `-`, `~`, `++`, `--`).
  static SourceEdit changePrefixOperator({
    required PrefixExpressionNode expression,
    required String newOperator,
  }) {
    return SourceEdit(
      offset: expression.operatorSpan.offset,
      length: expression.operatorSpan.length,
      replacement: newOperator,
    );
  }

  /// Renames the property of a `PropertyAccessExpressionNode` —
  /// e.g. `x.foo` → `x.bar`. The target and operator are preserved.
  static SourceEdit renamePropertyAccess({
    required PropertyAccessExpressionNode expression,
    required String newPropertyName,
  }) {
    return SourceEdit(
      offset: expression.propertyNameSpan.offset,
      length: expression.propertyNameSpan.length,
      replacement: newPropertyName,
    );
  }

  // ----------------------- More expression ops (M8.4) -------------

  /// Renames the prefix of a `PrefixedIdentifierExpressionNode` —
  /// e.g. `lib.foo` → `core.foo`.
  static SourceEdit renamePrefixedIdentifierPrefix({
    required PrefixedIdentifierExpressionNode expression,
    required String newPrefix,
  }) {
    return SourceEdit(
      offset: expression.prefixSpan.offset,
      length: expression.prefixSpan.length,
      replacement: newPrefix,
    );
  }

  /// Renames the trailing identifier of a `PrefixedIdentifierExpressionNode`
  /// — e.g. `lib.foo` → `lib.bar`.
  static SourceEdit renamePrefixedIdentifierName({
    required PrefixedIdentifierExpressionNode expression,
    required String newName,
  }) {
    return SourceEdit(
      offset: expression.identifierSpan.offset,
      length: expression.identifierSpan.length,
      replacement: newName,
    );
  }

  /// Changes the constructor name of an `InstanceCreationExpressionNode`
  /// — e.g. `Foo()` → `Bar()`, `Foo<int>.named()` → `Baz<int>.named()`.
  /// The new source replaces the entire constructor-name expression
  /// (which may include type args and named-ctor segments).
  static SourceEdit changeInstanceCreationConstructorName({
    required InstanceCreationExpressionNode expression,
    required String newConstructorNameSource,
  }) {
    return SourceEdit(
      offset: expression.constructorNameSpan.offset,
      length: expression.constructorNameSpan.length,
      replacement: newConstructorNameSource,
    );
  }

  /// Replaces the argument list of an `InstanceCreationExpressionNode`
  /// — e.g. `Foo(x)` → `Foo(x, y)`. The new source MUST include
  /// the surrounding parens.
  static SourceEdit changeInstanceCreationArguments({
    required InstanceCreationExpressionNode expression,
    required String newArgumentsSource,
  }) {
    return SourceEdit(
      offset: expression.argumentsSpan.offset,
      length: expression.argumentsSpan.length,
      replacement: newArgumentsSource,
    );
  }

  /// Changes the type of an `AsExpressionNode` — e.g. `x as int` →
  /// `x as num`.
  static SourceEdit changeAsExpressionType({
    required AsExpressionNode expression,
    required String newTypeSource,
  }) {
    return SourceEdit(
      offset: expression.typeSpan.offset,
      length: expression.typeSpan.length,
      replacement: newTypeSource,
    );
  }

  /// Changes the type of an `IsExpressionNode` — e.g. `x is int` →
  /// `x is num`. The `is` / `is!` operator is preserved.
  static SourceEdit changeIsExpressionType({
    required IsExpressionNode expression,
    required String newTypeSource,
  }) {
    return SourceEdit(
      offset: expression.typeSpan.offset,
      length: expression.typeSpan.length,
      replacement: newTypeSource,
    );
  }

  // ----------------------- Collection + function expr ops (M8.5) -

  /// Replaces the elements of a `ListLiteralExpressionNode` — e.g.
  /// `[1, 2]` → `[3, 4, 5]`. The new source should NOT include the
  /// surrounding brackets (they're preserved).
  static SourceEdit changeListLiteralElements({
    required ListLiteralExpressionNode expression,
    required String newElementsSource,
  }) {
    return SourceEdit(
      offset: expression.elementsSpan.offset,
      length: expression.elementsSpan.length,
      replacement: newElementsSource,
    );
  }

  /// Replaces the elements of a `SetOrMapLiteralExpressionNode`.
  static SourceEdit changeSetOrMapLiteralElements({
    required SetOrMapLiteralExpressionNode expression,
    required String newElementsSource,
  }) {
    return SourceEdit(
      offset: expression.elementsSpan.offset,
      length: expression.elementsSpan.length,
      replacement: newElementsSource,
    );
  }

  /// Replaces the fields of a `RecordLiteralExpressionNode` — e.g.
  /// `(1, 2)` → `(3, 4)`.
  static SourceEdit changeRecordLiteralFields({
    required RecordLiteralExpressionNode expression,
    required String newFieldsSource,
  }) {
    return SourceEdit(
      offset: expression.fieldsSpan.offset,
      length: expression.fieldsSpan.length,
      replacement: newFieldsSource,
    );
  }

  /// Replaces the body of a `FunctionExpressionNode` — e.g. swap an
  /// arrow body for a block, or change `=> x + 1` to `=> x * 2`.
  /// The new source must include the body's delimiter (the `=>`
  /// arrow for arrow forms or the `{ ... }` braces for block forms).
  static SourceEdit changeFunctionExpressionBody({
    required FunctionExpressionNode expression,
    required String newBodySource,
  }) {
    return SourceEdit(
      offset: expression.bodySpan.offset,
      length: expression.bodySpan.length,
      replacement: newBodySource,
    );
  }

  /// Replaces a single cascade section. `sectionIndex` selects which
  /// `..section` to rewrite. The new source MUST include the leading
  /// `..` (or `?..` for null-aware).
  static SourceEdit replaceCascadeSection({
    required CascadeExpressionNode expression,
    required int sectionIndex,
    required String newSectionSource,
  }) {
    if (sectionIndex < 0 || sectionIndex >= expression.sectionSpans.length) {
      throw ArgumentError(
        'sectionIndex $sectionIndex out of range '
        '[0, ${expression.sectionSpans.length})',
      );
    }
    final span = expression.sectionSpans[sectionIndex];
    return SourceEdit(
      offset: span.offset,
      length: span.length,
      replacement: newSectionSource,
    );
  }

  // ----------------------- Yield/break/continue ops (M8.1) -------

  /// Replaces the expression of a `yield` or `yield*` statement with
  /// `newExpressionSource`. The optional `*` is preserved verbatim.
  static SourceEdit changeYieldExpression({
    required YieldStatementNode statement,
    required String newExpressionSource,
  }) {
    return SourceEdit(
      offset: statement.expressionSpan.offset,
      length: statement.expressionSpan.length,
      replacement: newExpressionSource,
    );
  }

  /// Replaces the target label of a `break label;` statement. Throws
  /// on a bare `break;` (adding a label is deferred — it would require
  /// inserting whitespace + identifier between `break` and `;`).
  static SourceEdit changeBreakLabel({
    required BreakStatementNode statement,
    required String newLabel,
  }) {
    final span = statement.labelSpan;
    if (span == null) {
      throw ArgumentError(
        'Break statement has no label to replace. Adding a label '
        'to a bare `break;` is not yet supported.',
      );
    }
    return SourceEdit(
      offset: span.offset,
      length: span.length,
      replacement: newLabel,
    );
  }

  /// Replaces the target label of a `continue label;` statement.
  /// Throws on a bare `continue;`.
  static SourceEdit changeContinueLabel({
    required ContinueStatementNode statement,
    required String newLabel,
  }) {
    final span = statement.labelSpan;
    if (span == null) {
      throw ArgumentError(
        'Continue statement has no label to replace. Adding a label '
        'to a bare `continue;` is not yet supported.',
      );
    }
    return SourceEdit(
      offset: span.offset,
      length: span.length,
      replacement: newLabel,
    );
  }

  /// Renames a label declaration on a `LabeledStatementNode` — e.g.
  /// `outer: while (...)` → `mainLoop: while (...)`. Does NOT update
  /// `break outer;` / `continue outer;` references in the body —
  /// those are caller-responsible (or future work for a symbol-aware
  /// label rename op).
  static SourceEdit renameStatementLabel({
    required LabelNode label,
    required String newName,
  }) {
    return SourceEdit(
      offset: label.nameSpan.offset,
      length: label.nameSpan.length,
      replacement: newName,
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

/// AST visitor that collects `SimpleIdentifier` nodes whose `name`
/// equals [target], restricted to identifiers whose offset falls
/// within `[regionStart, regionEnd)`. Used by
/// `renameDeclaredPatternVariableWithReferences` to find references
/// inside a switch case's guard and body.
///
/// String literals and comments contain text that may LOOK like an
/// identifier reference but aren't AST `SimpleIdentifier` nodes —
/// they don't get matched. That's the right behavior for renaming a
/// local variable.
class _IdentifierCollector extends RecursiveAstVisitor<void> {
  _IdentifierCollector({
    required this.regionStart,
    required this.regionEnd,
    required this.target,
  });

  final int regionStart;
  final int regionEnd;
  final String target;
  final List<SimpleIdentifier> matches = [];

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.offset >= regionStart &&
        node.offset + node.length <= regionEnd &&
        node.name == target) {
      matches.add(node);
    }
    super.visitSimpleIdentifier(node);
  }
}

/// Collects `break label;` / `continue label;` references where the
/// label name matches `target`. Returns the label-name tokens (not
/// the full break/continue statement) so each rename edit covers just
/// the label identifier.
class _LabelReferenceCollector extends RecursiveAstVisitor<void> {
  _LabelReferenceCollector({
    required this.regionStart,
    required this.regionEnd,
    required this.target,
  });

  final int regionStart;
  final int regionEnd;
  final String target;
  final List<Token> matches = [];

  void _check(Token? labelToken) {
    if (labelToken == null) return;
    if (labelToken.offset >= regionStart &&
        labelToken.offset + labelToken.length <= regionEnd &&
        labelToken.lexeme == target) {
      matches.add(labelToken);
    }
  }

  @override
  void visitBreakStatement(BreakStatement node) {
    _check(node.label?.name);
    super.visitBreakStatement(node);
  }

  @override
  void visitContinueStatement(ContinueStatement node) {
    _check(node.label?.name);
    super.visitContinueStatement(node);
  }
}
