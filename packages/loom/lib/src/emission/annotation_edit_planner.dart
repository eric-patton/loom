import '../model/annotation.dart';
import 'source_edit.dart';

/// Edit operations on annotation arguments — the comma-separated
/// values inside an annotation's parentheses.
///
/// M10.0b operates on the structured `AnnotationArgumentNode` model
/// (M10.0a capture). The existing `replaceAnnotationArguments` in
/// `ClassStructureEditPlanner` replaces the ENTIRE parenthesized list
/// at once; these ops are finer-grained — add, remove, or change one
/// argument without touching the others.
///
/// Annotation-level ops (add/remove an entire annotation; replace the
/// whole argument list) remain in `ClassStructureEditPlanner` for
/// back-compat — they're annotation-positioning-aware, so they live
/// near the class-structure planner. The argument-level ops here are
/// position-agnostic — they work the same for any annotation
/// regardless of where it sits.
class AnnotationEditPlanner {
  AnnotationEditPlanner._();

  /// Adds a new argument to an annotation's parentheses.
  ///
  /// Handles three cases:
  ///   * No parens yet (bare `@Foo`) → inserts `(newArgumentSource)`.
  ///   * Empty parens (`@Foo()`) → inserts the arg between the parens.
  ///   * Non-empty parens → inserts `, newArgumentSource` before `)`.
  ///
  /// [newArgumentSource] is raw source for the argument — `"42"`,
  /// `"name: 'foo'"`, `"const Color(0xFF000000)"`. Caller is
  /// responsible for matching the existing arg style (positional vs.
  /// named) and for escaping.
  static SourceEdit addAnnotationArgument({
    required AnnotationNode annotation,
    required String newArgumentSource,
  }) {
    final argsSpan = annotation.argumentsSpan;
    if (argsSpan == null) {
      // Bare annotation: insert `(newArg)` after the name.
      return SourceEdit(
        offset: annotation.nameSpan.offset + annotation.nameSpan.length,
        length: 0,
        replacement: '($newArgumentSource)',
      );
    }
    if (annotation.arguments.isEmpty) {
      // Empty parens: insert between them. argsSpan covers `()` —
      // insert at offset+1 (right after `(`).
      return SourceEdit(
        offset: argsSpan.offset + 1,
        length: 0,
        replacement: newArgumentSource,
      );
    }
    // Non-empty: insert before the trailing `)`. That offset is
    // argsSpan.end - 1.
    return SourceEdit(
      offset: argsSpan.offset + argsSpan.length - 1,
      length: 0,
      replacement: ', $newArgumentSource',
    );
  }

  /// Removes the argument at [index] from an annotation. Handles
  /// the comma separator: if removing the first arg, also removes the
  /// trailing `, `; otherwise removes the leading `, `.
  ///
  /// Returns the edit. Throws `ArgumentError` if [index] is out of
  /// range or the annotation has no arguments.
  static SourceEdit removeAnnotationArgument({
    required AnnotationNode annotation,
    required int index,
    required String source,
  }) {
    final args = annotation.arguments;
    if (args.isEmpty) {
      throw ArgumentError('Annotation has no arguments to remove.');
    }
    if (index < 0 || index >= args.length) {
      throw RangeError.range(index, 0, args.length - 1, 'index');
    }
    final target = args[index];
    var start = target.sourceSpan.offset;
    var end = target.sourceSpan.offset + target.sourceSpan.length;

    if (args.length == 1) {
      // Only arg — just remove it; parens stay.
      return SourceEdit(
        offset: start,
        length: end - start,
        replacement: '',
      );
    }

    if (index == 0) {
      // Remove this arg + the comma and any whitespace after it,
      // up to (but not including) the next arg's start.
      final next = args[index + 1];
      end = next.sourceSpan.offset;
    } else {
      // Remove this arg + the comma and whitespace BEFORE it. Look
      // backwards from `start` to find the previous `,`.
      var cursor = start - 1;
      while (cursor >= 0) {
        final ch = source.codeUnitAt(cursor);
        if (ch == 0x2C /* , */) {
          start = cursor;
          break;
        }
        if (ch == 0x20 || ch == 0x09 || ch == 0x0A || ch == 0x0D) {
          cursor--;
          continue;
        }
        // Hit something unexpected — stop.
        break;
      }
    }
    return SourceEdit(
      offset: start,
      length: end - start,
      replacement: '',
    );
  }

  /// Replaces an argument's value with [newValueSource]. Preserves
  /// the `name:` prefix on named arguments.
  ///
  /// For named args, only the right-hand side of the `:` is replaced.
  /// For positional args, the entire argument span is replaced (same
  /// as the valueSpan).
  static SourceEdit changeAnnotationArgumentValue({
    required AnnotationArgumentNode argument,
    required String newValueSource,
  }) {
    final span = argument.valueSpan;
    return SourceEdit(
      offset: span.offset,
      length: span.length,
      replacement: newValueSource,
    );
  }

  /// Renames a named argument's label (`name: 'x'` → `label: 'x'`).
  /// Throws `ArgumentError` if [argument] is positional.
  static SourceEdit changeAnnotationArgumentName({
    required NamedAnnotationArgumentNode argument,
    required String newName,
  }) {
    return SourceEdit(
      offset: argument.nameSpan.offset,
      length: argument.nameSpan.length,
      replacement: newName,
    );
  }
}
