/// A single byte-range replacement against the source string.
///
/// Equivalent in shape to Dart Analysis Server's `SourceEdit`. The kernel
/// produces these; the caller applies them via `applySourceEdits`.
class SourceEdit {
  const SourceEdit({
    required this.offset,
    required this.length,
    required this.replacement,
  });

  final int offset;
  final int length;
  final String replacement;

  @override
  bool operator ==(Object other) =>
      other is SourceEdit &&
      other.offset == offset &&
      other.length == length &&
      other.replacement == replacement;

  @override
  int get hashCode => Object.hash(offset, length, replacement);

  @override
  String toString() =>
      'SourceEdit(@$offset+$length -> ${replacement.length} chars)';
}

/// Applies a list of `SourceEdit`s to `source` and returns the resulting
/// string. Edits are applied in reverse-offset order so each edit's offset
/// remains valid regardless of any other edit's effect on length.
///
/// Empty list is the identity case; this is what makes the spec's no-op
/// idempotence invariant trivially hold: `applySourceEdits(s, []) == s`.
String applySourceEdits(String source, List<SourceEdit> edits) {
  if (edits.isEmpty) {
    return source;
  }
  final sorted = <SourceEdit>[...edits]
    ..sort((a, b) => b.offset.compareTo(a.offset));
  var result = source;
  for (final edit in sorted) {
    result = result.replaceRange(
      edit.offset,
      edit.offset + edit.length,
      edit.replacement,
    );
  }
  return result;
}
