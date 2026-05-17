import 'package:dart_style/dart_style.dart';

/// Source-formatting service wrapping `package:dart_style`.
///
/// The editor's product invariant is byte-minimal diffs — `dart_style`
/// does not respect that, so formatting is OFF by default and opt-in
/// per document via `formatOnSaveProvider`. When enabled, the save
/// pipeline runs [tryFormat] on the post-edit source and persists the
/// formatted bytes if the formatter succeeded; if `dart_style` rejects
/// the source (parse error mid-edit), the unformatted bytes are saved
/// instead — never silently losing the edit.
class FormatService {
  FormatService();

  late final DartFormatter _formatter = DartFormatter(
    languageVersion: DartFormatter.latestLanguageVersion,
  );

  /// Returns the formatted source, or null if [source] could not be
  /// parsed. A null return is the caller's signal to fall back to the
  /// unformatted bytes.
  String? tryFormat(String source) {
    try {
      return _formatter.format(source);
    } on FormatterException {
      return null;
    } on Object {
      return null;
    }
  }
}
