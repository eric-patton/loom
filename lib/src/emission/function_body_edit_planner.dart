import 'package:analyzer/dart/analysis/utilities.dart';
// Hide analyzer's `PatternField` so the kernel-side `PatternField`
// (from function_body.dart) wins.
import 'package:analyzer/dart/ast/ast.dart' hide PatternField;
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
