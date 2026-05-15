import '../model/class_structure.dart';
import 'source_edit.dart';

/// Plans `SourceEdit`s for individual class-structure changes.
///
/// M7.0 first slice — five operations:
///   * `renameField` — change a field's name token
///   * `changeFieldType` — replace a field's type annotation (requires the
///     field to already have one)
///   * `changeFieldInitializer` — replace a field's initializer expression
///     (requires the field to already have one)
///   * `removeField` — delete the entire field declaration including
///     trailing whitespace up to (and consuming) the next newline
///   * `addField` — append a new field declaration at the end of the
///     class body, indented to match existing fields (or +2 spaces past
///     the class declaration's own indent if the body has no fields yet)
///
/// Deliberately omitted from this first slice:
///   * Adding a type annotation to an untyped field
///   * Adding an initializer to a bare field
///   * Reordering fields
///   * Edits that target field qualifiers (final/var/late/static)
///   * Multi-variable single-declaration handling
class ClassStructureEditPlanner {
  ClassStructureEditPlanner._();

  static SourceEdit renameField({
    required ClassFieldNode field,
    required String newName,
  }) {
    return SourceEdit(
      offset: field.nameSpan.offset,
      length: field.nameSpan.length,
      replacement: newName,
    );
  }

  /// Replaces the field's type annotation with `newType`. The field must
  /// already have a type annotation; throws `ArgumentError` for untyped
  /// fields (`var foo;`). Adding a type to an untyped field is a future
  /// milestone (it requires inserting the type token and a separator).
  static SourceEdit changeFieldType({
    required ClassFieldNode field,
    required String newType,
  }) {
    final span = field.typeSpan;
    if (span == null) {
      throw ArgumentError(
        'Field "${field.name}" has no type annotation; adding one is not '
        'supported in M7.0.',
      );
    }
    return SourceEdit(
      offset: span.offset,
      length: span.length,
      replacement: newType,
    );
  }

  /// Replaces the field's initializer expression with `newInitializerSource`.
  /// The field must already have an initializer; throws `ArgumentError`
  /// for bare fields. Adding an initializer to a bare field is a future
  /// milestone.
  static SourceEdit changeFieldInitializer({
    required ClassFieldNode field,
    required String newInitializerSource,
  }) {
    final span = field.initializerSpan;
    if (span == null) {
      throw ArgumentError(
        'Field "${field.name}" has no initializer; adding one is not '
        'supported in M7.0.',
      );
    }
    return SourceEdit(
      offset: span.offset,
      length: span.length,
      replacement: newInitializerSource,
    );
  }

  /// Removes the field declaration entirely, including trailing
  /// whitespace up to and including the next newline. Leaves the
  /// preceding line of source intact — so removing the second of three
  /// fields produces `<field1>\n<field3>` rather than `<field1>\n\n<field3>`.
  static SourceEdit removeField({
    required ClassFieldNode field,
    required String source,
  }) {
    final start = field.sourceSpan.offset;
    var end = field.sourceSpan.offset + field.sourceSpan.length;
    // Extend over trailing horizontal whitespace + one newline so the
    // gap collapses cleanly. Stops at the first non-whitespace byte.
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

  /// Inserts `newFieldSource` (e.g. `'final String email;'`) as the last
  /// field of the class body. Indentation is inferred from an existing
  /// field if any, otherwise from the class declaration's line indent
  /// plus two spaces.
  ///
  /// The inserted text does NOT include a leading newline — the planner
  /// adds one when there are existing members in the body, and skips it
  /// when the body is otherwise empty (so an empty `class Foo {}` ends up
  /// formatted as `class Foo {\n  final String email;\n}`).
  static SourceEdit addField({
    required ClassStructureNode parent,
    required String newFieldSource,
    required String source,
  }) {
    // Insert position is just before the closing `}` of the body.
    final closeOff = parent.bodySpan.offset + parent.bodySpan.length - 1;

    // Determine indent: prefer an existing field's indent. If the body
    // is otherwise empty, derive from the class declaration's line plus
    // two spaces.
    String fieldIndent;
    if (parent.fields.isNotEmpty) {
      fieldIndent = _lineIndentBefore(
        parent.fields.last.sourceSpan.offset,
        source,
      );
    } else if (parent.opaqueMemberSpans.isNotEmpty) {
      fieldIndent = _lineIndentBefore(
        parent.opaqueMemberSpans.last.offset,
        source,
      );
    } else {
      // Body is empty.
      final outerIndent = _lineIndentBefore(parent.classSpan.offset, source);
      fieldIndent = '$outerIndent  ';
    }

    // Walk back from `}` to find what's just before it.
    var probe = closeOff;
    while (probe > parent.bodySpan.offset) {
      final ch = source.codeUnitAt(probe - 1);
      if (ch == 0x20 || ch == 0x09 || ch == 0x0D || ch == 0x0A) {
        probe--;
      } else {
        break;
      }
    }
    final hasExistingContent = probe > parent.bodySpan.offset + 1;

    final String replacement;
    if (hasExistingContent) {
      // Body has at least one member; insert on a fresh line with the
      // body's indent. Use the same indentation as the existing tail
      // content so the new field aligns.
      replacement = '\n$fieldIndent$newFieldSource';
      return SourceEdit(
        offset: probe,
        length: 0,
        replacement: replacement,
      );
    }
    // Body has no content (or only whitespace) between `{` and `}`. Emit
    // `\n<indent>field\n<outerIndent>` so the closing brace ends up on
    // its own indented line.
    final outerIndent = _lineIndentBefore(parent.classSpan.offset, source);
    return SourceEdit(
      offset: parent.bodySpan.offset + 1,
      length: closeOff - (parent.bodySpan.offset + 1),
      replacement: '\n$fieldIndent$newFieldSource\n$outerIndent',
    );
  }

  /// Returns the run of horizontal whitespace immediately preceding
  /// `offset` on its line — i.e. the indentation of `offset`'s line.
  /// Duplicated from `ListEditHelpers._lineIndentBefore`; if a third
  /// consumer appears, promote to a shared utility module.
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
