/// Source-formatting service. M11 is intentionally a no-op: the editor's
/// product invariant is byte-minimal diffs, and `dart_style` does not
/// respect that. M12 will integrate `package:dart_style` behind an
/// opt-in flag (per-file or per-save), but the default stays off.
class FormatService {
  const FormatService();

  /// Returns [source] unchanged in M11. The hook exists so the editor's
  /// save pipeline already routes through a formatter and M12 only flips
  /// the implementation.
  String maybeFormat(String source) => source;
}
