import '../model/class_structure.dart';
import 'source_edit.dart';

/// Plans `SourceEdit`s for individual class-structure changes.
///
/// M7.0 surface (fields-only):
///   * `renameField` — change a field's name token
///   * `changeFieldType` — replace a field's type annotation (requires
///     the field to already have one)
///   * `changeFieldInitializer` — replace a field's initializer
///     expression (requires the field to already have one)
///   * `removeField` — delete the entire field declaration including
///     trailing whitespace up to (and consuming) the next newline
///   * `addField` — append a new field declaration at the end of the
///     class body
///
/// M7.1 surface additions (methods + constructors):
///   * `renameMethod` — change a method's name token (works on instance/
///     static methods, getters, setters)
///   * `changeMethodReturnType` — replace a method's return type
///     annotation (requires the method to already have one)
///   * `removeMember` — generic member-removal; works for any
///     `ClassMember` subtype. `removeField` is a thin wrapper that
///     delegates to this.
///   * `addMember` — generic member-append at end of class body.
///     `addField` is a thin wrapper that delegates to this.
///
/// M7.2 surface additions (parameter editing):
///   * `renameParameter` — change a parameter's name token
///   * `changeParameterType` — replace a parameter's type (requires
///     existing type)
///   * `changeParameterDefault` — replace a parameter's default value
///     (requires existing default)
///
/// Deliberately omitted (incremental — ship in M7.2.x+ as fixtures
/// demand):
///   * Adding/removing parameters (requires placement logic for
///     positional vs `[optional]` vs `{named}` sections, comma + bracket
///     handling)
///   * Edits to parameter qualifiers (final / const / required)
///   * Adding a type annotation to an untyped field or parameter
///   * Adding an initializer to a bare field
///   * Adding a default to a parameter without one
///   * Renaming a constructor (named ctor segment editing)
///   * Annotation editing (add / remove / replace annotations)
///   * Edits to qualifiers (final/var/late/static/const/factory)
///   * Reordering members
class ClassStructureEditPlanner {
  ClassStructureEditPlanner._();

  // ----------------------- Field operations -----------------------

  static SourceEdit renameField({
    required ClassFieldNode field,
    required String newName,
  }) =>
      SourceEdit(
        offset: field.nameSpan.offset,
        length: field.nameSpan.length,
        replacement: newName,
      );

  /// Replaces the field's type annotation with `newType`. The field must
  /// already have a type annotation; throws `ArgumentError` for untyped
  /// fields (`var foo;`).
  static SourceEdit changeFieldType({
    required ClassFieldNode field,
    required String newType,
  }) {
    final span = field.typeSpan;
    if (span == null) {
      throw ArgumentError(
        'Field "${field.name}" has no type annotation; adding one is not '
        'supported in M7.x.',
      );
    }
    return SourceEdit(
      offset: span.offset,
      length: span.length,
      replacement: newType,
    );
  }

  /// Replaces the field's initializer expression with `newInitializerSource`.
  /// The field must already have an initializer.
  static SourceEdit changeFieldInitializer({
    required ClassFieldNode field,
    required String newInitializerSource,
  }) {
    final span = field.initializerSpan;
    if (span == null) {
      throw ArgumentError(
        'Field "${field.name}" has no initializer; adding one is not '
        'supported in M7.x.',
      );
    }
    return SourceEdit(
      offset: span.offset,
      length: span.length,
      replacement: newInitializerSource,
    );
  }

  /// Convenience wrapper around [removeMember] for field removal.
  /// Kept for API compat with M7.0 callers.
  static SourceEdit removeField({
    required ClassFieldNode field,
    required String source,
  }) =>
      removeMember(member: field, source: source);

  /// Convenience wrapper around [addMember] for field addition.
  /// Kept for API compat with M7.0 callers.
  static SourceEdit addField({
    required ClassStructureNode parent,
    required String newFieldSource,
    required String source,
  }) =>
      addMember(
        parent: parent,
        newMemberSource: newFieldSource,
        source: source,
      );

  // ----------------------- Method operations -----------------------

  static SourceEdit renameMethod({
    required ClassMethodNode method,
    required String newName,
  }) =>
      SourceEdit(
        offset: method.nameSpan.offset,
        length: method.nameSpan.length,
        replacement: newName,
      );

  /// Replaces a method's return-type annotation with `newReturnType`.
  /// The method must already have a return type; throws `ArgumentError`
  /// otherwise (adding return-type annotations to bare methods is
  /// deferred — it requires inserting the type token and a separator).
  static SourceEdit changeMethodReturnType({
    required ClassMethodNode method,
    required String newReturnType,
  }) {
    final span = method.returnTypeSpan;
    if (span == null) {
      throw ArgumentError(
        'Method "${method.name}" has no return type; adding one is not '
        'supported in M7.x.',
      );
    }
    return SourceEdit(
      offset: span.offset,
      length: span.length,
      replacement: newReturnType,
    );
  }

  // --------------------- Parameter operations ---------------------

  static SourceEdit renameParameter({
    required ClassParameterNode parameter,
    required String newName,
  }) =>
      SourceEdit(
        offset: parameter.nameSpan.offset,
        length: parameter.nameSpan.length,
        replacement: newName,
      );

  /// Replaces a parameter's type annotation with `newType`. Requires the
  /// parameter to already have an explicit type; throws otherwise
  /// (adding a type to an untyped parameter — e.g. `{required this.x}` —
  /// requires insertion logic deferred to M7.2.x).
  static SourceEdit changeParameterType({
    required ClassParameterNode parameter,
    required String newType,
  }) {
    final span = parameter.typeSpan;
    if (span == null) {
      throw ArgumentError(
        'Parameter "${parameter.name}" has no type annotation; adding '
        'one is not supported in M7.2.',
      );
    }
    return SourceEdit(
      offset: span.offset,
      length: span.length,
      replacement: newType,
    );
  }

  /// Replaces a parameter's default value with `newDefaultSource`.
  /// Requires the parameter to already have a default; throws otherwise
  /// (adding a default to a parameter without one requires inserting
  /// the `=` separator and is deferred to M7.2.x).
  static SourceEdit changeParameterDefault({
    required ClassParameterNode parameter,
    required String newDefaultSource,
  }) {
    final span = parameter.defaultValueSpan;
    if (span == null) {
      throw ArgumentError(
        'Parameter "${parameter.name}" has no default value; adding one '
        'is not supported in M7.2.',
      );
    }
    return SourceEdit(
      offset: span.offset,
      length: span.length,
      replacement: newDefaultSource,
    );
  }

  // ----------------------- Generic operations -----------------------

  /// Removes any class member entirely, including trailing whitespace
  /// up to and including the next newline. Polymorphic over the
  /// `ClassMember` sealed type — same shape works for fields, methods,
  /// and constructors.
  static SourceEdit removeMember({
    required ClassMember member,
    required String source,
  }) {
    final start = member.sourceSpan.offset;
    var end = member.sourceSpan.offset + member.sourceSpan.length;
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

  /// Inserts `newMemberSource` (e.g. `'final String email;'`,
  /// `'void greet() {}'`, `'Foo.named(this.x);'`) at the end of the
  /// class body. Indentation is inferred from an existing member if any,
  /// otherwise from the class declaration's line indent plus two spaces.
  ///
  /// The inserted text does NOT include a leading newline — the planner
  /// adds one when there are existing members in the body, and skips it
  /// when the body is otherwise empty.
  static SourceEdit addMember({
    required ClassStructureNode parent,
    required String newMemberSource,
    required String source,
  }) {
    final closeOff = parent.bodySpan.offset + parent.bodySpan.length - 1;

    // Determine indent: prefer the last existing member's indent. If
    // the body is otherwise empty, derive from the class declaration's
    // line plus two spaces.
    String memberIndent;
    if (parent.members.isNotEmpty) {
      memberIndent = _lineIndentBefore(
        parent.members.last.sourceSpan.offset,
        source,
      );
    } else {
      final outerIndent = _lineIndentBefore(parent.classSpan.offset, source);
      memberIndent = '$outerIndent  ';
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

    if (hasExistingContent) {
      return SourceEdit(
        offset: probe,
        length: 0,
        replacement: '\n$memberIndent$newMemberSource',
      );
    }
    final outerIndent = _lineIndentBefore(parent.classSpan.offset, source);
    return SourceEdit(
      offset: parent.bodySpan.offset + 1,
      length: closeOff - (parent.bodySpan.offset + 1),
      replacement: '\n$memberIndent$newMemberSource\n$outerIndent',
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
