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
/// If-statement operations (M8.0b):
///   * `changeIfCondition` — replace the condition expression.
///   * Then/else block edits work via the `StatementBlock`-taking
///     ops above (`addStatement`, `removeStatement`, etc.) —
///     `IfStatementNode.thenBlock` / `elseBlock` plug right in.
///
/// Deliberately deferred (M8.0c / M8.1+):
///   * `else if` chains — currently opaqued by the parser.
///   * Bare-statement if bodies (`if (cond) doIt();`) — opaqued.
///   * Other control flow: for, while, switch, try.
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

    // Empty block: `{}` → `{\n  newStmt;\n}` with inferred indent.
    if (block.statements.isEmpty) {
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
