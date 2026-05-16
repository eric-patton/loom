// ignore_for_file: dangling_library_doc_comments

/// One-off: walk a directory tree, run the same logic
/// `parseWidgetTree` uses (first ClassDeclaration with a `build` method, then
/// its first top-level ReturnStatement's expression), and classify every
/// build-return that the kernel currently produces an `OpaqueNode` root for.
///
/// Categories:
///   A — return is not a constructor-shaped expression (switch, ternary,
///       method invocation on a target that isn't a SimpleIdentifier, etc.)
///   B — return is a named-constructor call (`Foo.bar(...)`)
///   C — return is a known-shape call (`Foo(...)`) to a class not in the
///       catalog
///   D — no return expression in the build body (parser would throw before
///       producing a model)
///
/// Reports counts + the top-N class names per category.
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:loom/loom.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart tool/opaque_root_diagnostic.dart <dir>');
    exitCode = 1;
    return;
  }
  final root = Directory(args.first);
  if (!root.existsSync()) {
    stderr.writeln('not a directory: ${args.first}');
    exitCode = 1;
    return;
  }

  var totalDartFiles = 0;
  var filesWithBuild = 0;
  var modeledRootClean = 0;
  var categoryA = 0;
  var categoryB = 0;
  var categoryC = 0;
  var categoryD = 0;
  var parseExceptionFiles = 0;

  final categoryASamples = <String>[];
  final categoryBClassNames = <String, int>{};
  final categoryCClassNames = <String, int>{};
  final categoryASampleSet = <String, int>{};

  for (final entity in root.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    totalDartFiles++;

    final String source;
    try {
      source = entity.readAsStringSync();
    } catch (_) {
      continue;
    }

    final result = parseString(content: source, throwIfDiagnostics: false);
    final unit = result.unit;

    // Mirror parseWidgetTree: first ClassDeclaration with a build method.
    MethodDeclaration? buildMethod;
    for (final decl in unit.declarations) {
      if (decl is! ClassDeclaration) continue;
      for (final member in decl.body.members) {
        if (member is MethodDeclaration && member.name.lexeme == 'build') {
          buildMethod = member;
          break;
        }
      }
      if (buildMethod != null) break;
    }
    if (buildMethod == null) continue;
    filesWithBuild++;

    // Mirror extractMethodReturnExpression: first top-level return.
    Expression? returned;
    final body = buildMethod.body;
    if (body is ExpressionFunctionBody) {
      returned = body.expression;
    } else if (body is BlockFunctionBody) {
      for (final stmt in body.block.statements) {
        if (stmt is ReturnStatement) {
          returned = stmt.expression;
          break;
        }
      }
    }
    if (returned == null) {
      categoryD++;
      continue;
    }

    // Run the actual parser to see what it produces — easier than
    // reimplementing the visitor's decisions.
    try {
      final model = parseWidgetTree(source);
      final root = model.root;
      if (root is WidgetNode || root is MethodReferenceNode) {
        modeledRootClean++;
        continue;
      }
      // OpaqueNode at root. Classify by inspecting the actual return expr.
      _classify(
        returned: returned,
        categoryASamples: categoryASamples,
        categoryASampleSet: categoryASampleSet,
        onA: () => categoryA++,
        onB: (className) {
          categoryB++;
          categoryBClassNames.update(className, (n) => n + 1,
              ifAbsent: () => 1);
        },
        onC: (className) {
          categoryC++;
          categoryCClassNames.update(className, (n) => n + 1,
              ifAbsent: () => 1);
        },
      );
    } on ParseException {
      parseExceptionFiles++;
    }
  }

  void printTopN(Map<String, int> counts, int n) {
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final entry in sorted.take(n)) {
      stdout.writeln('    ${entry.value.toString().padLeft(5)}  ${entry.key}');
    }
  }

  stdout.writeln('Opaque-root diagnostic for ${root.path}:');
  stdout.writeln('  Total .dart files:            $totalDartFiles');
  stdout.writeln('  Files with a build() method:  $filesWithBuild');
  stdout.writeln('  Modeled root (Widget/Method): $modeledRootClean');
  stdout.writeln('  Cat A (non-call expr):        $categoryA');
  stdout.writeln('  Cat B (named ctor):           $categoryB');
  stdout.writeln('  Cat C (unknown class):        $categoryC');
  stdout.writeln('  Cat D (no return):            $categoryD');
  stdout.writeln('  ParseException:               $parseExceptionFiles');
  stdout.writeln('');

  if (categoryASampleSet.isNotEmpty) {
    stdout.writeln('Category A — return-expression AST kinds (top 10):');
    printTopN(categoryASampleSet, 10);
    stdout.writeln('');
  }
  if (categoryBClassNames.isNotEmpty) {
    stdout.writeln('Category B — named-constructor class names (top 15):');
    printTopN(categoryBClassNames, 15);
    stdout.writeln('');
  }
  if (categoryCClassNames.isNotEmpty) {
    stdout.writeln('Category C — unknown class names (top 25):');
    printTopN(categoryCClassNames, 25);
    stdout.writeln('');
  }
}

void _classify({
  required Expression returned,
  required List<String> categoryASamples,
  required Map<String, int> categoryASampleSet,
  required void Function() onA,
  required void Function(String className) onB,
  required void Function(String className) onC,
}) {
  // Constructor-call-shaped?
  if (returned is InstanceCreationExpression) {
    final type = returned.constructorName.type;
    final prefixToken = type.importPrefix;
    final localName = type.name.lexeme;
    final explicitNamedCtor = returned.constructorName.name?.name;
    if (prefixToken != null && explicitNamedCtor == null) {
      // `Prefix.Name(args)` shape — treated as named-constructor in parser.
      onB('${prefixToken.name.lexeme}.$localName');
      return;
    }
    if (explicitNamedCtor != null) {
      onB('$localName.$explicitNamedCtor');
      return;
    }
    onC(localName);
    return;
  }
  if (returned is MethodInvocation) {
    final target = returned.target;
    if (target == null) {
      onC(returned.methodName.name);
      return;
    }
    if (target is SimpleIdentifier) {
      onB('${target.name}.${returned.methodName.name}');
      return;
    }
    // Method invocation on something more complex (a chain, etc.) — cat A.
    final kind = returned.runtimeType.toString();
    onA();
    categoryASampleSet.update(kind, (n) => n + 1, ifAbsent: () => 1);
    return;
  }
  // Anything else: switch expression, conditional, function expression, etc.
  final kind = returned.runtimeType.toString();
  onA();
  categoryASampleSet.update(kind, (n) => n + 1, ifAbsent: () => 1);
}
