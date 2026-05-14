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
/// Validates inputs and throws `ArgumentError` if:
///   - Any edit has a negative offset or length
///   - Any edit's `offset + length` exceeds `source.length`
///   - Two edits' ranges overlap
///   - Two edits share the same offset (regardless of length — order is
///     ambiguous when both target the same starting point, because the
///     "should the insert land before or after the replacement?" question
///     has no canonical answer)
///
/// Empty list is the identity case; this is what makes the spec's no-op
/// idempotence invariant trivially hold: `applySourceEdits(s, []) == s`.
String applySourceEdits(String source, List<SourceEdit> edits) {
  if (edits.isEmpty) {
    return source;
  }

  // Per-edit bounds checks.
  for (final edit in edits) {
    if (edit.offset < 0) {
      throw ArgumentError.value(
        edit,
        'edits',
        'SourceEdit offset must be non-negative',
      );
    }
    if (edit.length < 0) {
      throw ArgumentError.value(
        edit,
        'edits',
        'SourceEdit length must be non-negative',
      );
    }
    if (edit.offset + edit.length > source.length) {
      throw ArgumentError.value(
        edit,
        'edits',
        'SourceEdit range [${edit.offset}, ${edit.offset + edit.length}) '
            'exceeds source length ${source.length}',
      );
    }
  }

  // Pairwise overlap / ambiguous-order check via ascending-offset sort.
  // Two edits at the same offset always throw — the only previously-allowed
  // case (one pure insert + one with length > 0 at the same offset) passed
  // validation in one input order and threw "overlap" in the other, which
  // made application non-deterministic. Treating any same-offset pair as
  // ambiguous is the simpler invariant and matches the underlying reality:
  // there is no canonical answer to "does the insert land before or after
  // the replacement?".
  final ascending = <SourceEdit>[...edits]
    ..sort((a, b) => a.offset.compareTo(b.offset));
  for (var i = 1; i < ascending.length; i++) {
    final prev = ascending[i - 1];
    final curr = ascending[i];
    if (curr.offset == prev.offset) {
      throw ArgumentError(
        'Two SourceEdits at offset ${curr.offset} '
        '($prev and $curr); application order is ambiguous',
      );
    }
    if (curr.offset < prev.offset + prev.length) {
      throw ArgumentError(
        'Overlapping SourceEdits: '
        '[${prev.offset}, ${prev.offset + prev.length}) and '
        '[${curr.offset}, ${curr.offset + curr.length})',
      );
    }
  }

  // Apply in descending-offset order so each prior edit's offset stays valid.
  final descending = <SourceEdit>[...edits]
    ..sort((a, b) => b.offset.compareTo(a.offset));
  var result = source;
  for (final edit in descending) {
    result = result.replaceRange(
      edit.offset,
      edit.offset + edit.length,
      edit.replacement,
    );
  }
  return result;
}
