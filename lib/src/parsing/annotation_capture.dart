import 'package:analyzer/dart/ast/ast.dart';

import '../model/annotation.dart';
import '../model/source_span.dart';

/// Captures each `Annotation` in a metadata list as an `AnnotationNode`.
///
/// Handles both bare annotations (`@override`) and call-form
/// (`@JsonKey(name: 'foo')`); for prefixed annotations
/// (`@meta.required`) the full dotted name is captured as `name`.
///
/// Argument internals (positional/named) are modeled too (M10.0b) so
/// downstream edits can target individual arguments.
List<AnnotationNode> captureAnnotations(
  NodeList<Annotation> metadata,
  String source,
) {
  if (metadata.isEmpty) {
    return const <AnnotationNode>[];
  }
  final out = <AnnotationNode>[];
  for (final ann in metadata) {
    final nameNode = ann.name;
    final nameText = source.substring(
      nameNode.offset,
      nameNode.offset + nameNode.length,
    );
    final args = ann.arguments;
    final argsSource = args == null
        ? null
        : source.substring(args.offset, args.offset + args.length);
    final argsSpan = args == null
        ? null
        : SourceSpan(offset: args.offset, length: args.length);
    final arguments = args == null
        ? const <AnnotationArgumentNode>[]
        : _captureArguments(args, source);
    out.add(
      AnnotationNode(
        name: nameText,
        nameSpan: SourceSpan(
          offset: nameNode.offset,
          length: nameNode.length,
        ),
        argumentsSource: argsSource,
        argumentsSpan: argsSpan,
        sourceSpan: SourceSpan(offset: ann.offset, length: ann.length),
        arguments: arguments,
      ),
    );
  }
  return out;
}

List<AnnotationArgumentNode> _captureArguments(
  ArgumentList list,
  String source,
) {
  final out = <AnnotationArgumentNode>[];
  for (final arg in list.arguments) {
    if (arg is NamedArgument) {
      final nameToken = arg.name;
      final expr = arg.argumentExpression;
      out.add(
        NamedAnnotationArgumentNode(
          name: nameToken.lexeme,
          nameSpan: SourceSpan(
            offset: nameToken.offset,
            length: nameToken.length,
          ),
          valueSource: source.substring(expr.offset, expr.end),
          valueSpan: SourceSpan(
            offset: expr.offset,
            length: expr.length,
          ),
          sourceSpan: SourceSpan(offset: arg.offset, length: arg.length),
        ),
      );
    } else {
      out.add(
        PositionalAnnotationArgumentNode(
          valueSource: source.substring(arg.offset, arg.end),
          valueSpan: SourceSpan(offset: arg.offset, length: arg.length),
          sourceSpan: SourceSpan(offset: arg.offset, length: arg.length),
        ),
      );
    }
  }
  return out;
}
