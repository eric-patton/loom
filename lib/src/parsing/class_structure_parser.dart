import 'package:analyzer/dart/analysis/utilities.dart';
// Hide analyzer's `ClassMember` to avoid clashing with the loom-side
// `ClassMember` sealed type defined in `model/class_structure.dart`.
// The two are unrelated (analyzer's models the AST node; loom's models
// the visual model).
import 'package:analyzer/dart/ast/ast.dart' hide ClassMember;
import 'package:analyzer/dart/ast/token.dart';

import '../model/class_structure.dart';
import '../model/source_span.dart';
import 'base_visitor.dart' show ParseException;

/// Parses a Dart source string into a `ClassStructureModel`.
///
/// M7.0 first slice: walks the first `ClassDeclaration` in the unit and
/// surfaces its field declarations as `ClassFieldNode`s. Non-field members
/// (methods, constructors, getters/setters) are preserved as opaque
/// source-span entries — `M7.0` does not model their content.
///
/// Throws `ParseException` if the file contains no class declaration.
///
/// Multiple classes in one file: the parser picks the FIRST class. Same
/// convention as the widget parser (M1's settled decision). Modeling
/// secondary classes would require introducing a multi-class root, which
/// is M9 territory (cross-file / multi-class).
ClassStructureModel parseClassStructure(String source) {
  final result = parseString(content: source, throwIfDiagnostics: false);
  final unit = result.unit;
  final diagnostics = <ParseDiagnostic>[
    for (final error in result.errors)
      ParseDiagnostic(
        span: SourceSpan(offset: error.offset, length: error.length),
        message: error.message,
      ),
  ];

  for (final declaration in unit.declarations) {
    if (declaration is! ClassDeclaration) {
      continue;
    }

    final classSpan = SourceSpan(
      offset: declaration.offset,
      length: declaration.length,
    );

    // ClassDeclaration.body is a sealed `ClassBody` (analyzer 13). Only
    // `BlockClassBody` carries the `{ ... }` braces we want to anchor
    // edits against; `EmptyClassBody` is the `class Foo;` form which
    // has no body to edit.
    final body = declaration.body;
    if (body is! BlockClassBody) {
      // Empty body (`class Foo;`) — nothing modelable for M7.0. Continue
      // to the next class declaration; if none have a block body, we
      // throw at the bottom of the loop.
      continue;
    }
    final bodySpan = SourceSpan(
      offset: body.leftBracket.offset,
      length: body.rightBracket.offset +
          body.rightBracket.length -
          body.leftBracket.offset,
    );

    final members = <ClassMember>[];

    for (final member in body.members) {
      if (member is FieldDeclaration) {
        _appendFields(member, source, members);
      } else if (member is MethodDeclaration) {
        members.add(_buildMethodNode(member, source));
      } else if (member is ConstructorDeclaration) {
        members.add(_buildConstructorNode(member, source));
      } else {
        members.add(
          OpaqueClassMember(
            sourceSpan: SourceSpan(
              offset: member.offset,
              length: member.length,
            ),
          ),
        );
      }
    }

    // analyzer 13: `ClassDeclaration.name` was replaced by
    // `namePart` (a `ClassNamePart`), whose `typeName` is the actual
    // class-name token.
    return ClassStructureModel(
      root: ClassStructureNode(
        className: declaration.namePart.typeName.lexeme,
        classSpan: classSpan,
        bodySpan: bodySpan,
        members: members,
      ),
      diagnostics: diagnostics,
    );
  }

  throw const ParseException('No class declaration found in this file');
}

/// Walks a `FieldDeclaration` and appends one `ClassFieldNode` per
/// declared variable. A single source declaration may declare multiple
/// variables (`final String a, b;`), each becoming its own node; all
/// share the outer declaration span.
void _appendFields(
  FieldDeclaration member,
  String source,
  List<ClassMember> out,
) {
  final sharedSpan = SourceSpan(offset: member.offset, length: member.length);
  final typeNode = member.fields.type;
  final typeName = typeNode?.toSource();
  final typeSpan = typeNode == null
      ? null
      : SourceSpan(offset: typeNode.offset, length: typeNode.length);

  final keyword = member.fields.keyword;
  final isFinal = keyword != null && keyword.keyword == Keyword.FINAL;
  final isVar = keyword != null && keyword.keyword == Keyword.VAR;
  final isLate = member.fields.lateKeyword != null;
  final isStatic = member.isStatic;

  for (final variable in member.fields.variables) {
    final initializer = variable.initializer;
    final initializerSource = initializer == null
        ? null
        : source.substring(
            initializer.offset,
            initializer.offset + initializer.length,
          );
    final initializerSpan = initializer == null
        ? null
        : SourceSpan(
            offset: initializer.offset,
            length: initializer.length,
          );

    out.add(
      ClassFieldNode(
        name: variable.name.lexeme,
        nameSpan: SourceSpan(
          offset: variable.name.offset,
          length: variable.name.length,
        ),
        typeName: typeName,
        typeSpan: typeSpan,
        initializerSource: initializerSource,
        initializerSpan: initializerSpan,
        isFinal: isFinal,
        isVar: isVar,
        isLate: isLate,
        isStatic: isStatic,
        sourceSpan: sharedSpan,
      ),
    );
  }
}

ClassMethodNode _buildMethodNode(MethodDeclaration member, String source) {
  final returnType = member.returnType;
  final returnTypeText = returnType?.toSource();
  final returnTypeSpan = returnType == null
      ? null
      : SourceSpan(offset: returnType.offset, length: returnType.length);

  // Getters have no parameter list.
  final params = member.parameters;
  final parametersSource = params == null
      ? null
      : source.substring(params.offset, params.offset + params.length);
  final parametersSpan = params == null
      ? null
      : SourceSpan(offset: params.offset, length: params.length);

  final body = member.body;
  final bodySpan = SourceSpan(offset: body.offset, length: body.length);

  return ClassMethodNode(
    name: member.name.lexeme,
    nameSpan: SourceSpan(
      offset: member.name.offset,
      length: member.name.length,
    ),
    returnType: returnTypeText,
    returnTypeSpan: returnTypeSpan,
    parametersSource: parametersSource,
    parametersSpan: parametersSpan,
    bodySpan: bodySpan,
    isStatic: member.isStatic,
    isAbstract: member.isAbstract,
    isGetter: member.isGetter,
    isSetter: member.isSetter,
    isOperator: member.isOperator,
    isAsync: body.isAsynchronous,
    isGenerator: body.isGenerator,
    sourceSpan: SourceSpan(offset: member.offset, length: member.length),
  );
}

ClassConstructorNode _buildConstructorNode(
  ConstructorDeclaration member,
  String source,
) {
  final params = member.parameters;
  final parametersSource =
      source.substring(params.offset, params.offset + params.length);
  final parametersSpan =
      SourceSpan(offset: params.offset, length: params.length);

  // Initializer list: starts at `separator` (the `:` token before the
  // first initializer), ends at the last initializer. Null if no
  // initializers AND no separator.
  String? initializerListSource;
  SourceSpan? initializerListSpan;
  final separator = member.separator;
  if (separator != null && member.initializers.isNotEmpty) {
    final start = separator.offset;
    final last = member.initializers.last;
    final end = last.offset + last.length;
    initializerListSource = source.substring(start, end);
    initializerListSpan = SourceSpan(offset: start, length: end - start);
  }

  // `typeName` is the class name in the constructor source. In analyzer
  // 13's "new syntax" path (`new C()`), typeName is null and the class
  // name lives elsewhere. M7.1 only supports the classic shape; if
  // typeName is null, fall back to spanning the constructor's first
  // token for the className anchor.
  final typeName = member.typeName;
  final String className;
  final SourceSpan classNameSpan;
  if (typeName != null) {
    className = typeName.name;
    classNameSpan =
        SourceSpan(offset: typeName.offset, length: typeName.length);
  } else {
    // Fallback: use the first token of the declaration as the anchor.
    // This is rare in practice (only old-syntax + new-keyword shape).
    final firstToken = member.beginToken;
    className = firstToken.lexeme;
    classNameSpan = SourceSpan(
      offset: firstToken.offset,
      length: firstToken.length,
    );
  }

  final body = member.body;
  final bodySpan = SourceSpan(offset: body.offset, length: body.length);

  return ClassConstructorNode(
    className: className,
    classNameSpan: classNameSpan,
    namedConstructorName: member.name?.lexeme,
    namedConstructorSpan: member.name == null
        ? null
        : SourceSpan(
            offset: member.name!.offset,
            length: member.name!.length,
          ),
    parametersSource: parametersSource,
    parametersSpan: parametersSpan,
    initializerListSource: initializerListSource,
    initializerListSpan: initializerListSpan,
    bodySpan: bodySpan,
    isConst: member.constKeyword != null,
    isFactory: member.factoryKeyword != null,
    sourceSpan: SourceSpan(offset: member.offset, length: member.length),
  );
}
