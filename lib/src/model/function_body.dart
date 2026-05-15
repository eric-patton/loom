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
    required this.bodySpan,
    required this.innerSpan,
    required this.statements,
    this.diagnostics = const <ParseDiagnostic>[],
  });

  /// Span of the full body, from the opening `{` to the closing `}`
  /// (inclusive).
  final SourceSpan bodySpan;

  /// Span of the body's interior — between `{` and `}` (exclusive of the
  /// braces themselves). Used as the anchor for `addStatement` to know
  /// where to insert.
  final SourceSpan innerSpan;

  /// Statements in source order. Pattern-match on subtype to distinguish
  /// declared variables, expression statements, return statements, and
  /// opaque pass-through.
  final List<StatementNode> statements;

  final List<ParseDiagnostic> diagnostics;

  @override
  String toString() => 'FunctionBodyModel(${statements.length} statement(s)'
      '${diagnostics.isEmpty ? '' : ', ${diagnostics.length} diagnostic(s)'})';
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

/// A statement kind not yet modeled by M8.0a — `if`, `for`, `while`,
/// `switch`, `try`, etc. Preserves the source verbatim through any
/// edit to surrounding statements; the kernel makes no guarantees
/// about edits that would target opaque content.
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
