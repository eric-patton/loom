import 'package:analyzer/dart/ast/ast.dart';

import '../catalog/widget_catalog.dart';
import '../model/list_slot_style.dart';
import '../model/node.dart';
import '../model/property_value.dart';
import '../model/source_span.dart';
import '../model/style_hints.dart';
import 'base_visitor.dart';

// Re-export the shared types so existing callers that imported
// `widget_visitor.dart` for `ParseException` / `extractMethodReturnExpression`
// keep working without churn.
export 'base_visitor.dart' show ParseException, extractMethodReturnExpression;

/// Walks a widget expression and produces a `ModelNode`.
///
/// M6.1 Phase 2: the shared scaffolding lives in [BaseVisitor]; this class
/// adds the three widget-specific hooks (catalog lookup, `WidgetNode`
/// construction, and `EdgeInsets.all` / `Color` property recognition).
///
/// `localCatalog` lets the parser inject project-discovered widget classes
/// (intra-file pre-scan; see `project_widget_discovery.dart`). Lookups
/// consult the static `WidgetCatalog` first, then fall through to
/// `localCatalog` — so a project class can't accidentally shadow a
/// framework widget of the same name.
class WidgetVisitor extends BaseVisitor {
  WidgetVisitor(
    super.source, {
    super.classMethods,
    this.localCatalog = const <String, WidgetSpec>{},
  });

  /// Project-defined widget classes discovered in the same compilation
  /// unit. Empty `WidgetSpec` per entry — recognition only, no slot
  /// inference yet.
  final Map<String, WidgetSpec> localCatalog;

  @override
  CatalogSpec? specFor(String className) =>
      WidgetCatalog.specFor(className) ?? localCatalog[className];

  @override
  ModelNode buildModeledNode({
    required String className,
    required String? namedConstructor,
    required Map<String, PropertyValue> properties,
    required Map<String, List<ModelNode>> childSlots,
    required Map<String, ListSlotStyle> childSlotStyles,
    required SourceSpan sourceSpan,
    required StyleHints styleHints,
  }) {
    return WidgetNode(
      className: className,
      namedConstructor: namedConstructor,
      properties: properties,
      childSlots: childSlots,
      childSlotStyles: childSlotStyles,
      sourceSpan: sourceSpan,
      styleHints: styleHints,
    );
  }

  /// Widget-specific property-value recognition: `EdgeInsets.all(N)` and
  /// `Color(0xFF…)` literals get their own modeled variants so emission can
  /// re-render them faithfully. Anything else falls through to opaque.
  @override
  PropertyValue? customConstructorPropertyValue(CallInfo call) {
    if (call.className == 'EdgeInsets' && call.namedConstructor == 'all') {
      return _edgeInsetsAll(call);
    }
    if (call.className == 'Color' && call.namedConstructor == null) {
      return _colorLiteral(call);
    }
    return null;
  }

  PropertyValue? _edgeInsetsAll(CallInfo call) {
    final args = call.argumentList.arguments;
    if (args.length != 1) {
      return null;
    }
    final arg = args.first;
    if (arg is IntegerLiteral) {
      final value = arg.value;
      if (value == null) {
        return null;
      }
      return EdgeInsetsAllValue(
        amount: value,
        amountIsDouble: false,
        span: call.span,
      );
    }
    if (arg is DoubleLiteral) {
      return EdgeInsetsAllValue(
        amount: arg.value,
        amountIsDouble: true,
        span: call.span,
      );
    }
    // Negative literals: `EdgeInsets.all(-8)` is parsed as
    // PrefixExpression('-', IntegerLiteral(8)) rather than a single signed
    // literal. Recognize the shape so the editor sees a structured value.
    if (arg is PrefixExpression && arg.operator.lexeme == '-') {
      final inner = arg.operand;
      if (inner is IntegerLiteral) {
        final v = inner.value;
        if (v == null) return null;
        return EdgeInsetsAllValue(
          amount: -v,
          amountIsDouble: false,
          span: call.span,
        );
      }
      if (inner is DoubleLiteral) {
        return EdgeInsetsAllValue(
          amount: -inner.value,
          amountIsDouble: true,
          span: call.span,
        );
      }
    }
    return null;
  }

  PropertyValue? _colorLiteral(CallInfo call) {
    final args = call.argumentList.arguments;
    if (args.length != 1) {
      return null;
    }
    final arg = args.first;
    if (arg is! IntegerLiteral) {
      return null;
    }
    final value = arg.value;
    if (value == null) {
      return null;
    }
    return ColorValue(argbValue: value, span: call.span);
  }
}
