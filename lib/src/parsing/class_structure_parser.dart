import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
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

    final fields = <ClassFieldNode>[];
    final opaqueMemberSpans = <SourceSpan>[];

    for (final member in body.members) {
      if (member is FieldDeclaration) {
        // A single FieldDeclaration may declare multiple variables
        // (`final String a, b;`). Each becomes its own ClassFieldNode,
        // but all share the same outer source span (the full declaration).
        // M7.0 treats this case as best-effort — multi-variable
        // declarations are unusual in modern Dart style, and structural
        // edits target the whole declaration as a unit.
        final sharedSpan = SourceSpan(
          offset: member.offset,
          length: member.length,
        );
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

          fields.add(
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
      } else {
        opaqueMemberSpans.add(
          SourceSpan(offset: member.offset, length: member.length),
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
        fields: fields,
        opaqueMemberSpans: opaqueMemberSpans,
      ),
      diagnostics: diagnostics,
    );
  }

  throw const ParseException('No class declaration found in this file');
}
