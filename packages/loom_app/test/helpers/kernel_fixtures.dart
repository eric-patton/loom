import 'package:loom_app/src/services/kernel_adapter.dart';

/// Convenience constructors for kernel types in tests. The spans are
/// dummy and only valid for "in-memory" assertions — anything that
/// applies a SourceEdit must use real spans from a real parse.

StringLiteralValue stringValue(
  String text, {
  bool useDoubleQuotes = false,
  int offset = 0,
}) =>
    StringLiteralValue(
      value: text,
      usesDoubleQuotes: useDoubleQuotes,
      span: SourceSpan(offset: offset, length: text.length + 2),
    );

NumLiteralValue intValue(int v, {int offset = 0}) => NumLiteralValue(
      value: v,
      isDouble: false,
      span: SourceSpan(offset: offset, length: 1),
    );

NumLiteralValue doubleValue(double v, {int offset = 0}) => NumLiteralValue(
      value: v,
      isDouble: true,
      span: SourceSpan(offset: offset, length: 1),
    );

BoolLiteralValue boolValue(bool v, {int offset = 0}) => BoolLiteralValue(
      value: v,
      span: SourceSpan(offset: offset, length: 1),
    );

OpaquePropertyValue opaqueValue(String text, {int offset = 0}) =>
    OpaquePropertyValue(
      sourceText: text,
      span: SourceSpan(offset: offset, length: text.length),
    );

NullLiteralValue nullValue({int offset = 0}) =>
    NullLiteralValue(span: SourceSpan(offset: offset, length: 4));

EnumReferenceValue enumRef(
  String typeName,
  String memberName, {
  int offset = 0,
}) =>
    EnumReferenceValue(
      typeName: typeName,
      memberName: memberName,
      span: SourceSpan(
        offset: offset,
        length: typeName.length + memberName.length + 1,
      ),
    );

WidgetNode widgetNode({
  required String className,
  String? namedConstructor,
  Map<String, PropertyValue> properties = const <String, PropertyValue>{},
  Map<String, List<ModelNode>> childSlots = const <String, List<ModelNode>>{},
  int offset = 0,
}) =>
    WidgetNode(
      className: className,
      namedConstructor: namedConstructor,
      properties: properties,
      childSlots: childSlots,
      sourceSpan: SourceSpan(offset: offset, length: className.length + 2),
      styleHints: const StyleHints(),
    );

OpaqueNode opaqueNode(String text, {int offset = 0}) => OpaqueNode(
      sourceSpan: SourceSpan(offset: offset, length: text.length),
      sourceText: text,
    );

WidgetTreeModel treeOf(ModelNode root) => WidgetTreeModel(root: root);
