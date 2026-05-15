import 'annotation.dart';
import 'source_span.dart';

export 'annotation.dart';

/// Snapshot of the top-level names declared in a single Dart file.
/// Built by `parseFileSymbols`.
class FileSymbols {
  FileSymbols({required List<FileSymbolDeclaration> declarations})
      : declarations = List.unmodifiable(declarations);

  /// Top-level declarations in source order.
  final List<FileSymbolDeclaration> declarations;

  /// Returns the declared names (without spans). Computed eagerly
  /// since this is the most-used view.
  Set<String> get names => {for (final d in declarations) d.name};

  /// Returns the declaration that introduces [name], or null if this
  /// file doesn't declare it.
  FileSymbolDeclaration? findDeclaration(String name) {
    for (final d in declarations) {
      if (d.name == name) return d;
    }
    return null;
  }

  @override
  String toString() => 'FileSymbols(${declarations.length} declaration(s))';
}

/// One top-level declaration's metadata. Doesn't carry the full AST —
/// just the name, the relevant spans for editing, and any annotations
/// attached to the declaration.
class FileSymbolDeclaration {
  FileSymbolDeclaration({
    required this.name,
    required this.nameSpan,
    required this.declarationSpan,
    required this.kind,
    List<AnnotationNode> annotations = const <AnnotationNode>[],
  }) : annotations = List.unmodifiable(annotations);

  /// The declared name (e.g. `'MyClass'`, `'helper'`, `'kPi'`).
  final String name;

  /// Span of just the name token. Useful for renaming.
  final SourceSpan nameSpan;

  /// Span of the full declaration (from the first keyword/annotation
  /// to the closing `}` / `;`).
  final SourceSpan declarationSpan;

  /// The declaration kind. Useful for distinguishing classes from
  /// functions, etc.
  final DeclarationKind kind;

  /// Annotations attached to the declaration (`@JsonSerializable()`,
  /// `@freezed`, `@pragma('vm:entry-point')`, etc.), in source order.
  /// Empty when the declaration has no annotations.
  ///
  /// M10.0a capture. The declaration site of a top-level class /
  /// function / variable / typedef carries the annotations; the
  /// individual members within a class are captured separately by
  /// `parseClassStructure` (M7.2).
  final List<AnnotationNode> annotations;

  @override
  String toString() => 'FileSymbolDeclaration($name: ${kind.name})';
}

/// Kinds of top-level declarations a file can introduce.
enum DeclarationKind {
  classKind,
  mixin,
  enumKind,
  extensionKind,
  extensionType,
  function,
  typedef,
  topLevelVariable,
}
