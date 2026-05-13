import 'source_span.dart';

/// Surface-syntax detail captured for each list-shaped child slot so
/// structural edits (M3) can preserve the list's existing style — its
/// trailing-comma state and whether it was written single-line or
/// multi-line. Single-shaped slots (`child: foo`) don't have one.
class ListSlotStyle {
  const ListSlotStyle({
    required this.bracketsSpan,
    required this.hasTrailingComma,
    required this.isMultiLine,
  });

  /// Byte range of the list literal `[...]`, including both brackets.
  final SourceSpan bracketsSpan;

  /// Whether the list literal ends with a trailing comma:
  /// `[a, b,]` -> `true`, `[a, b]` -> `false`.
  final bool hasTrailingComma;

  /// Whether the list literal occupies more than one source line.
  /// Used to pick the separator style when inserting new elements.
  final bool isMultiLine;

  @override
  bool operator ==(Object other) =>
      other is ListSlotStyle &&
      other.bracketsSpan == bracketsSpan &&
      other.hasTrailingComma == hasTrailingComma &&
      other.isMultiLine == isMultiLine;

  @override
  int get hashCode => Object.hash(bracketsSpan, hasTrailingComma, isMultiLine);

  @override
  String toString() {
    final flags = <String>[
      if (hasTrailingComma) 'trailingComma',
      if (isMultiLine) 'multiLine' else 'singleLine',
    ];
    return 'ListSlotStyle(${flags.join(', ')})';
  }
}
