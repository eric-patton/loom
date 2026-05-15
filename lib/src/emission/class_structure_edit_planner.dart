import '../model/class_structure.dart';
import '../model/source_span.dart';
import 'source_edit.dart';

/// Which logical section of a parameter list to operate on.
///
/// Dart parameter lists have up to three sections, in this order:
///   * required positional — bare params before any brackets
///   * optional positional — params in `[ ... ]` brackets (mutually
///     exclusive with named in any given list)
///   * named — params in `{ ... }` braces (mutually exclusive with
///     optional positional)
enum ParameterSection { positionalRequired, positionalOptional, named }

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
/// M7.2.1 surface additions (parameter add/remove):
///   * `appendParameter` — append to existing section of parameter list
///   * `removeParameter` — delete + separator cleanup, preserves
///     surrounding section brackets
///
/// M7.3 surface additions (annotation editing):
///   * `addClassAnnotation` — prepend annotation before class decl
///   * `addMemberAnnotation` — prepend annotation before member
///   * `addParameterAnnotation` — inline annotation before parameter
///   * `removeAnnotation` — delete annotation + adjacent whitespace/newline
///   * `replaceAnnotationArguments` — replace `(...)` portion (requires
///     existing args list)
///
/// Deliberately omitted (incremental — ship in M7.2.2 / M7.4+ as
/// fixtures demand):
///   * Section creation (appending to empty `named`/`positionalOptional`)
///   * Empty-section bracket cleanup after `removeParameter` drains a section
///   * Edits to parameter qualifiers (final / const / required)
///   * Adding a type annotation to an untyped field or parameter
///   * Adding an initializer to a bare field
///   * Adding a default to a parameter without one
///   * Adding `(...)` to a bare annotation
///   * Renaming a constructor (named ctor segment editing)
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

  // ----------------------- Parameter add/remove (M7.2.1) -----------

  /// Appends a new parameter at the end of the requested section of
  /// `parent`'s parameter list. `parent` must be a `ClassMethodNode` or
  /// `ClassConstructorNode` with a parameter list (throws for getters).
  ///
  /// Requires the section to already contain at least one parameter — or,
  /// for `positionalRequired`, allows the list to be entirely empty or
  /// to have non-required-positional sections (the new param goes before
  /// the opening `[` or `{`).
  ///
  /// `newParameterSource` is the raw parameter declaration text without
  /// surrounding separators (e.g., `'required String email'`,
  /// `'int age = 0'`, `'this.name'`).
  ///
  /// Deferred to M7.2.2: appending to an EMPTY `positionalOptional` or
  /// `named` section (requires inserting `[...]` or `{...}` brackets and
  /// the preceding `, ` separator).
  static SourceEdit appendParameter({
    required ClassMember parent,
    required String newParameterSource,
    required ParameterSection section,
    required String source,
  }) {
    final (parameters, paramListSpan) = _unpackParameterList(parent);

    final inSection =
        parameters.where((p) => _isInSection(p, section)).toList();

    final separator = _detectParamSeparator(parameters, paramListSpan, source);

    if (inSection.isNotEmpty) {
      // Most common path: insert after the last param in the section.
      final anchor = inSection.last.sourceSpan.end;
      return SourceEdit(
        offset: anchor,
        length: 0,
        replacement: '$separator$newParameterSource',
      );
    }

    // Section is empty. Only positionalRequired has a working v1
    // path; the others need section creation.
    if (section != ParameterSection.positionalRequired) {
      throw ArgumentError(
        'Cannot append to empty $section section (requires inserting '
        'brackets; deferred to M7.2.2). Use raw parametersSpan '
        'replacement for now if you need to create a new section.',
      );
    }

    if (parameters.isEmpty) {
      // List is `()`. Insert just after the `(`.
      return SourceEdit(
        offset: paramListSpan.offset + 1,
        length: 0,
        replacement: newParameterSource,
      );
    }

    // List has other-section params; positionalRequired section is
    // empty (e.g., `({named: 1})`). Insert before the section opener
    // (the `[` or `{`) along with a separator `newParam, `.
    final firstParam = parameters.first;
    var probe = firstParam.sourceSpan.offset - 1;
    while (probe >= 0 && _isWhitespace(source.codeUnitAt(probe))) {
      probe--;
    }
    // probe is now at the `{` or `[` opener (or some unexpected token —
    // but in well-formed Dart this should always be a section opener).
    final bracketOffset = probe;
    return SourceEdit(
      offset: bracketOffset,
      length: 0,
      replacement: '$newParameterSource, ',
    );
  }

  /// Removes a parameter from its containing list. Handles three cases:
  ///
  /// * Non-first param: walks backward through whitespace and one `,`
  ///   to find the preceding separator; deletes from there through the
  ///   param's end.
  /// * First param with a following param/section: walks forward through
  ///   `,` and whitespace to find the next significant token; deletes
  ///   from the param's offset to there. Stops at section openers
  ///   (`[` or `{`) so the section's brackets stay intact.
  /// * Sole param (or last in a list with no following sections):
  ///   deletes just the parameter itself; surrounding brackets remain.
  ///
  /// If removing the last parameter in a section drains that section
  /// to empty, the section's brackets (`[]` or `{}`) are LEFT behind.
  /// Removing empty section brackets is M7.2.2 territory.
  static SourceEdit removeParameter({
    required ClassParameterNode parameter,
    required String source,
  }) {
    var start = parameter.sourceSpan.offset;
    var end = parameter.sourceSpan.end;

    // Try to find a preceding `,` (skipping whitespace).
    var backProbe = start - 1;
    while (backProbe >= 0 && _isWhitespace(source.codeUnitAt(backProbe))) {
      backProbe--;
    }
    if (backProbe >= 0 && source.codeUnitAt(backProbe) == 0x2C) {
      // Preceding `,` found — include it in the deletion.
      start = backProbe;
    } else {
      // First in list (or section, when no other sections precede).
      // Consume forward separator: one `,` then whitespace, but only up
      // to the next non-whitespace non-comma character. Stop short of
      // section openers (`[`/`{`) so the brackets are preserved.
      var fwdProbe = end;
      if (fwdProbe < source.length && source.codeUnitAt(fwdProbe) == 0x2C) {
        fwdProbe++;
      }
      while (fwdProbe < source.length &&
          _isWhitespace(source.codeUnitAt(fwdProbe))) {
        fwdProbe++;
      }
      end = fwdProbe;
    }

    return SourceEdit(
      offset: start,
      length: end - start,
      replacement: '',
    );
  }

  // ----------------------- Annotation operations (M7.3) ---------

  /// Prepends `annotationSource` (e.g. `'@override'`, `'@JsonKey(name: \"x\")'`)
  /// before a class declaration. The new annotation lands on its own line
  /// with the same indent as the class declaration.
  static SourceEdit addClassAnnotation({
    required ClassStructureNode parent,
    required String annotationSource,
    required String source,
  }) {
    final indent = _lineIndentBefore(parent.classSpan.offset, source);
    return SourceEdit(
      offset: parent.classSpan.offset,
      length: 0,
      replacement: '$annotationSource\n$indent',
    );
  }

  /// Prepends `annotationSource` before a class member (field / method /
  /// constructor). The new annotation lands on its own line with the
  /// same indent as the member.
  static SourceEdit addMemberAnnotation({
    required ClassMember member,
    required String annotationSource,
    required String source,
  }) {
    final indent = _lineIndentBefore(member.sourceSpan.offset, source);
    return SourceEdit(
      offset: member.sourceSpan.offset,
      length: 0,
      replacement: '$annotationSource\n$indent',
    );
  }

  /// Prepends `annotationSource` before a parameter. The new annotation
  /// is placed on the same line as the parameter, separated by a single
  /// space (most common Dart style for inline parameter annotations).
  static SourceEdit addParameterAnnotation({
    required ClassParameterNode parameter,
    required String annotationSource,
  }) {
    return SourceEdit(
      offset: parameter.sourceSpan.offset,
      length: 0,
      replacement: '$annotationSource ',
    );
  }

  /// Removes an annotation. Deletes the annotation source plus any
  /// trailing whitespace through (and including) the next newline if
  /// present — collapsing the line so removed annotations don't leave
  /// blank lines behind.
  ///
  /// Works for class-level, member-level, and parameter-level
  /// annotations. For inline parameter annotations (no trailing
  /// newline), deletes through trailing horizontal whitespace instead.
  static SourceEdit removeAnnotation({
    required AnnotationNode annotation,
    required String source,
  }) {
    final start = annotation.sourceSpan.offset;
    var end = annotation.sourceSpan.end;
    // Extend over trailing horizontal whitespace + at most one newline.
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

  /// Replaces an annotation's arguments with `newArgumentsSource`. The
  /// new source should include the surrounding parentheses
  /// (`'(name: \"foo\")'`). Requires the annotation to already have an
  /// arguments list; throws otherwise (adding parens to a bare
  /// annotation is deferred to a future milestone).
  static SourceEdit replaceAnnotationArguments({
    required AnnotationNode annotation,
    required String newArgumentsSource,
  }) {
    final span = annotation.argumentsSpan;
    if (span == null) {
      throw ArgumentError(
        'Annotation @${annotation.name} has no arguments list to replace. '
        'Adding `(...)` to a bare annotation is deferred to a future '
        'milestone.',
      );
    }
    return SourceEdit(
      offset: span.offset,
      length: span.length,
      replacement: newArgumentsSource,
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

  // ----------------------- Internal helpers -----------------------

  /// Pulls `(parameters, parametersSpan)` out of any modeled
  /// constructor-or-method node. Throws if the node is not a method or
  /// constructor, or if it's a getter (which has no parameter list).
  static (List<ClassParameterNode>, SourceSpan) _unpackParameterList(
    ClassMember parent,
  ) {
    SourceSpan? span;
    List<ClassParameterNode> parameters;
    switch (parent) {
      case final ClassMethodNode m:
        span = m.parametersSpan;
        parameters = m.parameters;
      case final ClassConstructorNode c:
        span = c.parametersSpan;
        parameters = c.parameters;
      case ClassFieldNode():
      case OpaqueClassMember():
        throw ArgumentError(
          'Parameter operations require a method or constructor target; '
          'got ${parent.runtimeType}.',
        );
    }
    if (span == null) {
      throw ArgumentError(
        'Target has no parameter list (likely a getter). '
        'Use a method with parameters or a constructor instead.',
      );
    }
    return (parameters, span);
  }

  static bool _isInSection(ClassParameterNode p, ParameterSection s) {
    switch (s) {
      case ParameterSection.positionalRequired:
        return p.isPositional && p.isRequired;
      case ParameterSection.positionalOptional:
        return p.isPositional && p.isOptional;
      case ParameterSection.named:
        return p.isNamed;
    }
  }

  /// Looks at the gap between adjacent parameters to figure out what
  /// separator pattern to use for an insertion. Falls back to `', '` for
  /// single-line lists or where the heuristic doesn't apply.
  static String _detectParamSeparator(
    List<ClassParameterNode> parameters,
    SourceSpan paramListSpan,
    String source,
  ) {
    if (parameters.length >= 2) {
      // The first inter-param gap is the most reliable separator pattern.
      final between = source.substring(
        parameters[0].sourceSpan.end,
        parameters[1].sourceSpan.offset,
      );
      // Only adopt the natural separator if it doesn't contain commentary;
      // a `// ...` between params would otherwise get duplicated.
      if (!between.contains('//') && !between.contains('/*')) {
        return between;
      }
    }
    if (parameters.length == 1) {
      // Multi-line single-param list. Infer indent from the param's line.
      final listText =
          source.substring(paramListSpan.offset, paramListSpan.end);
      if (listText.contains('\n')) {
        final paramOffset = parameters[0].sourceSpan.offset;
        var lineStart = paramOffset;
        while (lineStart > 0 && source.codeUnitAt(lineStart - 1) != 0x0A) {
          lineStart--;
        }
        final indent = source.substring(lineStart, paramOffset);
        return ',\n$indent';
      }
    }
    return ', ';
  }

  static bool _isWhitespace(int ch) =>
      ch == 0x20 || ch == 0x09 || ch == 0x0A || ch == 0x0D;

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
