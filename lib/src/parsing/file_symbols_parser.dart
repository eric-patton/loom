import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart' hide ClassMember;
import 'package:analyzer/dart/ast/token.dart';

import '../model/file_symbols.dart';
import '../model/source_span.dart';

/// Parses a Dart compilation unit's top-level declarations into a
/// `FileSymbols` snapshot — names declared at the file's top level
/// plus their declaration spans.
///
/// "Top-level" means the unit's direct children: classes, mixins,
/// extensions (named only), enums, functions, top-level variables,
/// and typedefs. Methods/fields inside a class are NOT included —
/// they're not top-level names.
///
/// Doesn't resolve imports or re-exports; that's the project-level
/// `resolveSymbol` op (M9.3).
FileSymbols parseFileSymbols(String source) {
  final result = parseString(content: source, throwIfDiagnostics: false);
  final declarations = <FileSymbolDeclaration>[];

  for (final decl in result.unit.declarations) {
    if (decl is ClassDeclaration) {
      declarations.add(
        _makeSymbol(decl.namePart.typeName, decl, DeclarationKind.classKind),
      );
    } else if (decl is MixinDeclaration) {
      declarations.add(_makeSymbol(decl.name, decl, DeclarationKind.mixin));
    } else if (decl is EnumDeclaration) {
      declarations.add(
        _makeSymbol(decl.namePart.typeName, decl, DeclarationKind.enumKind),
      );
    } else if (decl is ExtensionDeclaration) {
      final name = decl.name;
      if (name != null) {
        declarations.add(
          _makeSymbol(name, decl, DeclarationKind.extensionKind),
        );
      }
      // Unnamed extensions don't declare a top-level name.
    } else if (decl is ExtensionTypeDeclaration) {
      // Extension type's name lives on its primary constructor.
      declarations.add(
        _makeSymbol(
          decl.primaryConstructor.typeName,
          decl,
          DeclarationKind.extensionType,
        ),
      );
    } else if (decl is FunctionDeclaration) {
      declarations.add(
        _makeSymbol(decl.name, decl, DeclarationKind.function),
      );
    } else if (decl is FunctionTypeAlias) {
      declarations.add(_makeSymbol(decl.name, decl, DeclarationKind.typedef));
    } else if (decl is GenericTypeAlias) {
      declarations.add(_makeSymbol(decl.name, decl, DeclarationKind.typedef));
    } else if (decl is TopLevelVariableDeclaration) {
      for (final v in decl.variables.variables) {
        declarations.add(FileSymbolDeclaration(
          name: v.name.lexeme,
          nameSpan: SourceSpan(offset: v.name.offset, length: v.name.length),
          declarationSpan: SourceSpan(offset: decl.offset, length: decl.length),
          kind: DeclarationKind.topLevelVariable,
        ));
      }
    }
    // ClassTypeAlias (`class Foo = A with B;`) — could add later.
  }

  return FileSymbols(declarations: declarations);
}

FileSymbolDeclaration _makeSymbol(
  Token nameToken,
  AstNode declarationNode,
  DeclarationKind kind,
) {
  return FileSymbolDeclaration(
    name: nameToken.lexeme,
    nameSpan: SourceSpan(offset: nameToken.offset, length: nameToken.length),
    declarationSpan: SourceSpan(
      offset: declarationNode.offset,
      length: declarationNode.length,
    ),
    kind: kind,
  );
}
