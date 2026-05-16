/// Surface-syntax details captured per `WidgetNode` so emission can restore
/// exactly what the user wrote. See Settled Decisions Q1/Q3 in DEVLOG.md.
class StyleHints {
  const StyleHints({
    this.hasConst = false,
    this.hasNew = false,
    this.hasTrailingComma = false,
  });

  final bool hasConst;
  final bool hasNew;
  final bool hasTrailingComma;

  @override
  bool operator ==(Object other) =>
      other is StyleHints &&
      other.hasConst == hasConst &&
      other.hasNew == hasNew &&
      other.hasTrailingComma == hasTrailingComma;

  @override
  int get hashCode => Object.hash(hasConst, hasNew, hasTrailingComma);

  @override
  String toString() {
    final flags = <String>[
      if (hasConst) 'const',
      if (hasNew) 'new',
      if (hasTrailingComma) 'trailingComma',
    ];
    return flags.isEmpty ? 'StyleHints()' : 'StyleHints(${flags.join(', ')})';
  }
}
