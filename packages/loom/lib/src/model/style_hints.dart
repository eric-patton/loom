/// Surface-syntax details captured per `WidgetNode` so emission can restore
/// exactly what the user wrote. See Settled Decisions Q1/Q3 in DEVLOG.md.
///
/// [isMultiLine] is a hint for whole-widget re-emission (e.g. "wrap this
/// widget with a parent", "extract this subtree to a method"). Today's
/// edit-planner ops are byte-range replacements that never re-emit a
/// modeled widget whole — they only edit specific properties or splice
/// children — so this hint is observational and does NOT affect existing
/// edits. It IS captured at parse time so the future re-emission path
/// can preserve the user's original shape.
class StyleHints {
  const StyleHints({
    this.hasConst = false,
    this.hasNew = false,
    this.hasTrailingComma = false,
    this.isMultiLine = false,
  });

  final bool hasConst;
  final bool hasNew;
  final bool hasTrailingComma;

  /// True iff the constructor call's argument list spans multiple lines
  /// in the source. Determined at parse time by whether the call's
  /// opening and closing parens are on different lines.
  final bool isMultiLine;

  @override
  bool operator ==(Object other) =>
      other is StyleHints &&
      other.hasConst == hasConst &&
      other.hasNew == hasNew &&
      other.hasTrailingComma == hasTrailingComma &&
      other.isMultiLine == isMultiLine;

  @override
  int get hashCode =>
      Object.hash(hasConst, hasNew, hasTrailingComma, isMultiLine);

  @override
  String toString() {
    final flags = <String>[
      if (hasConst) 'const',
      if (hasNew) 'new',
      if (hasTrailingComma) 'trailingComma',
      if (isMultiLine) 'multiLine',
    ];
    return flags.isEmpty ? 'StyleHints()' : 'StyleHints(${flags.join(', ')})';
  }
}
