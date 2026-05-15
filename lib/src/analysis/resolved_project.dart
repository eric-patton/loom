import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart' hide ClassMember;
import 'package:analyzer/dart/ast/visitor.dart';

/// Optional resolved-analysis wrapper around analyzer's
/// `AnalysisContextCollection` (M10.2).
///
/// Loom's primary parsing path is `parseString` — fast, sync, and only
/// produces an unresolved AST. That covers most kernel ops because the
/// kernel reasons about source structure, not types. For the cases
/// where type information matters (precise rename, "what type is this
/// expression?", "is X assignable to Y?"), `ResolvedProject` provides
/// async access to fully-resolved analysis results backed by the
/// analyzer's full semantic pipeline.
///
/// Trade-offs vs. the unresolved path:
///   * **Heavier** — initializes a full analysis context; needs an
///     SDK on disk; reads `package_config.json` from the project.
///   * **Async** — `getResolvedUnit` returns a `Future`.
///   * **File-based** — `includedPaths` must be absolute paths on the
///     real filesystem. Use a temp directory for in-memory workflows.
///     `OverlayResourceProvider` integration is deferred — most
///     OutSystems-trajectory consumers will either write to a workspace
///     directory on disk (visual-editor save), or use the unresolved
///     path entirely.
///
/// Caller MUST call `dispose()` when done to release resources.
///
/// This class is opt-in — the rest of the kernel works without it.
class ResolvedProject {
  ResolvedProject._({
    required AnalysisContextCollection collection,
    required List<String> includedPaths,
  })  : _collection = collection,
        _includedPaths = includedPaths;

  /// Opens a `ResolvedProject` rooted at one or more directories or
  /// files. All paths must be absolute and normalized.
  ///
  /// [sdkPath] should be the absolute path to a Dart SDK installation
  /// (the directory containing `bin/dart` / `bin/dart.exe`). If null,
  /// the analyzer uses its default lookup logic (typically the SDK
  /// the host process is running on).
  static ResolvedProject open({
    required List<String> includedPaths,
    String? sdkPath,
  }) {
    final collection = AnalysisContextCollection(
      includedPaths: includedPaths,
      sdkPath: sdkPath,
    );
    return ResolvedProject._(
      collection: collection,
      includedPaths: includedPaths,
    );
  }

  final AnalysisContextCollection _collection;
  // ignore: unused_field
  final List<String> _includedPaths;

  /// Returns the fully-resolved unit for [filePath] (absolute path),
  /// or null if the file cannot be resolved (not in any context, has
  /// an invalid path, etc.). Diagnostics are available on the result.
  Future<ResolvedUnitResult?> getResolvedUnit(String filePath) async {
    final context = _collection.contextFor(filePath);
    final result = await context.currentSession.getResolvedUnit(filePath);
    return result is ResolvedUnitResult ? result : null;
  }

  /// Releases resources held by the underlying analysis context.
  /// MUST be called when done.
  Future<void> dispose() => _collection.dispose();

  // ----------------------- Type queries (M10.2b) -----------------

  /// Returns the type of a top-level declaration's signature, as
  /// displayString (e.g. `'int'`, `'String?'`, `'Future<List<T>>'`).
  ///
  /// For a function: its return type.
  /// For a class / mixin / enum / extension type: the class name itself
  /// (since the "type" of a class declaration IS the class type).
  /// For a top-level variable: its declared / inferred type.
  /// For a typedef: the aliased type.
  ///
  /// Returns null when no declaration matches [name], or when the
  /// resolved unit can't be obtained.
  Future<String?> typeOfTopLevelDeclaration({
    required String filePath,
    required String name,
  }) async {
    final result = await getResolvedUnit(filePath);
    if (result == null) return null;
    for (final decl in result.unit.declarations) {
      if (decl is FunctionDeclaration && decl.name.lexeme == name) {
        // The element model gives us the return type even when not
        // written explicitly.
        final fragment = decl.declaredFragment;
        if (fragment == null) return null;
        return fragment.element.returnType.getDisplayString();
      }
      if (decl is TopLevelVariableDeclaration) {
        for (final v in decl.variables.variables) {
          if (v.name.lexeme == name) {
            final fragment = v.declaredFragment;
            if (fragment == null) return null;
            return fragment.element.type.getDisplayString();
          }
        }
      }
      if (decl is ClassDeclaration && decl.namePart.typeName.lexeme == name) {
        return decl.namePart.typeName.lexeme;
      }
      if (decl is MixinDeclaration && decl.name.lexeme == name) {
        return decl.name.lexeme;
      }
      if (decl is EnumDeclaration && decl.namePart.typeName.lexeme == name) {
        return decl.namePart.typeName.lexeme;
      }
      if (decl is ExtensionTypeDeclaration &&
          decl.primaryConstructor.typeName.lexeme == name) {
        return decl.primaryConstructor.typeName.lexeme;
      }
    }
    return null;
  }

  /// Returns the element-precise location of a top-level symbol [name]
  /// as seen from [filePath].
  ///
  /// "Element-precise" means it uses the analyzer's resolved name
  /// lookup (the same logic the compiler uses) — so it correctly
  /// distinguishes between two same-named classes from different
  /// imports, and accounts for show/hide combinators, prefixes,
  /// shadowing, and re-exports.
  ///
  /// Returns null when:
  ///   * The resolved unit isn't available.
  ///   * No top-level symbol with [name] is in scope from [filePath].
  ///   * The matched element doesn't have an addressable declaration
  ///     (e.g., it's synthetic, from a summary, or in the SDK).
  ///
  /// This is the type-aware counterpart to M9.3's
  /// `ProjectModel.resolveSymbol` — same intent, more precision.
  Future<ResolvedSymbolLocation?> resolveSymbolPrecise({
    required String filePath,
    required String name,
  }) async {
    final result = await getResolvedUnit(filePath);
    if (result == null) return null;
    // Scope lives on the LibraryFragment (the file's compilation unit
    // representation), not on the LibraryElement.
    final lookup = result.libraryFragment.scope.lookup(name);
    final element = lookup.getter ?? lookup.setter;
    if (element == null) return null;

    final fragment = element.firstFragment;
    final libraryFragment = fragment.libraryFragment;
    if (libraryFragment == null) return null;
    final source = libraryFragment.source;

    final nameOffset = fragment.nameOffset;
    final fragmentName = fragment.name;
    if (nameOffset == null || fragmentName == null) return null;

    return ResolvedSymbolLocation(
      filePath: source.fullName,
      name: fragmentName,
      nameOffset: nameOffset,
      nameLength: fragmentName.length,
      elementKind: element.kind.name,
    );
  }

  /// Returns the static type of the expression at [offset] within
  /// [filePath], or null if no expression of that exact span is found.
  ///
  /// Specifically, finds the SMALLEST Expression node whose source
  /// span starts at [offset] (so callers can target a specific
  /// identifier, literal, or sub-expression by passing its known
  /// offset from `parseString` analysis).
  Future<String?> typeOfExpressionAt({
    required String filePath,
    required int offset,
  }) async {
    final result = await getResolvedUnit(filePath);
    if (result == null) return null;
    final visitor = _ExpressionAtOffsetVisitor(offset);
    result.unit.accept(visitor);
    final expr = visitor.found;
    if (expr == null) return null;
    return expr.staticType?.getDisplayString();
  }
}

/// The element-precise location of a top-level symbol resolved
/// through the analyzer's full semantic pipeline.
///
/// Differs from M9.3's `SymbolLocation` (which is name-based and
/// produced by `ProjectModel.resolveSymbol`) in three ways:
///   * Backed by the actual `Element` the analyzer matched — no
///     false positives from same-named symbols in different
///     imports.
///   * Includes the analyzer's `elementKind` label ("class",
///     "topLevelFunction", etc.).
///   * Works for symbols from `dart:*` and `package:*` libraries
///     when the package is in the analysis config, which the
///     name-based resolver can't reach.
class ResolvedSymbolLocation {
  const ResolvedSymbolLocation({
    required this.filePath,
    required this.name,
    required this.nameOffset,
    required this.nameLength,
    required this.elementKind,
  });

  /// Absolute path of the file that DECLARES the symbol.
  final String filePath;

  /// The declared name as the analyzer sees it.
  final String name;

  /// Offset of the name token within the declaring file.
  final int nameOffset;

  /// Length of the name token.
  final int nameLength;

  /// Analyzer's element-kind label — `'class'`, `'mixin'`,
  /// `'topLevelFunction'`, `'topLevelVariable'`, `'enum'`,
  /// `'getter'`, `'setter'`, etc.
  final String elementKind;

  @override
  String toString() =>
      'ResolvedSymbolLocation($name @ $filePath, kind=$elementKind)';
}

class _ExpressionAtOffsetVisitor extends GeneralizingAstVisitor<void> {
  _ExpressionAtOffsetVisitor(this.targetOffset);

  final int targetOffset;
  Expression? found;

  @override
  void visitExpression(Expression node) {
    if (node.offset == targetOffset) {
      // Prefer the SMALLEST (most-nested) expression starting here.
      if (found == null || node.length < found!.length) {
        found = node;
      }
    }
    super.visitExpression(node);
  }
}
