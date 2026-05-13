import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/syntactic_entity.dart';
import 'package:analyzer/dart/ast/token.dart';

import '../catalog/widget_catalog.dart';
import '../model/property_value.dart';
import '../model/source_span.dart';
import '../model/style_hints.dart';
import '../model/widget_node.dart';

/// Thrown when the visitor encounters Dart it doesn't model in M1.
///
/// In future milestones, many of these will be replaced by `OpaqueNode`
/// fallbacks (see PROJECT_SPEC.md M4). For now, M1 fixtures are hand-crafted
/// or hand-picked to stay inside the supported subset, so any throw is a
/// real bug.
class ParseException implements Exception {
  const ParseException(this.message, [this.span]);

  final String message;
  final SourceSpan? span;

  @override
  String toString() =>
      'ParseException: $message${span == null ? '' : ' at $span'}';
}

class WidgetVisitor {
  WidgetNode convertWidget(Expression expr) {
    final call = _tryExtractCall(expr);
    if (call == null) {
      throw ParseException(
        'Expected widget constructor call, got ${expr.runtimeType}',
        _span(expr),
      );
    }
    if (call.namedConstructor != null) {
      throw ParseException(
        'Named constructors not supported for widgets in M1 '
        '(${call.className}.${call.namedConstructor})',
        call.span,
      );
    }
    final spec = WidgetCatalog.specFor(call.className);
    if (spec == null) {
      throw ParseException(
          'Unknown widget class: ${call.className}', call.span);
    }

    final properties = <String, PropertyValue>{};
    final childSlots = <String, List<WidgetNode>>{};

    final args = call.argumentList.arguments;
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (arg is NamedExpression) {
        final name = arg.name.label.name;
        final slotShape = spec.childSlots[name];
        if (slotShape != null) {
          childSlots[name] = _collectChildren(arg.expression, slotShape);
        } else {
          properties[name] = _convertProperty(arg.expression);
        }
      } else {
        final propName = spec.positionalToProperty[i];
        if (propName == null) {
          throw ParseException(
            'Positional argument $i not modeled for ${call.className}',
            _span(arg),
          );
        }
        properties[propName] = _convertProperty(arg);
      }
    }

    return WidgetNode(
      className: call.className,
      properties: properties,
      childSlots: childSlots,
      sourceSpan: call.span,
      styleHints: _hintsFromCall(call),
    );
  }

  List<WidgetNode> _collectChildren(
    Expression slotExpr,
    ChildSlotShape shape,
  ) {
    if (shape == ChildSlotShape.list) {
      if (slotExpr is! ListLiteral) {
        throw ParseException(
          'Expected list literal for list-shaped child slot',
          _span(slotExpr),
        );
      }
      final out = <WidgetNode>[];
      for (final element in slotExpr.elements) {
        if (element is! Expression) {
          throw ParseException(
            'Non-expression collection element (${element.runtimeType})',
            _span(element),
          );
        }
        out.add(convertWidget(element));
      }
      return out;
    }
    return <WidgetNode>[convertWidget(slotExpr)];
  }

  PropertyValue _convertProperty(Expression expr) {
    if (expr is SimpleStringLiteral) {
      return StringLiteralValue(value: expr.value, span: _span(expr));
    }
    if (expr is IntegerLiteral) {
      final value = expr.value;
      if (value == null) {
        throw ParseException(
          'Integer literal out of range or unparseable',
          _span(expr),
        );
      }
      return NumLiteralValue(
        value: value,
        isDouble: false,
        span: _span(expr),
      );
    }
    if (expr is DoubleLiteral) {
      return NumLiteralValue(
        value: expr.value,
        isDouble: true,
        span: _span(expr),
      );
    }
    if (expr is BooleanLiteral) {
      return BoolLiteralValue(value: expr.value, span: _span(expr));
    }
    if (expr is NullLiteral) {
      return NullLiteralValue(span: _span(expr));
    }
    if (expr is PrefixedIdentifier) {
      return EnumReferenceValue(
        typeName: expr.prefix.name,
        memberName: expr.identifier.name,
        span: _span(expr),
      );
    }
    final call = _tryExtractCall(expr);
    if (call != null) {
      return _convertConstructorPropertyValue(call);
    }
    throw ParseException(
      'Unsupported property value: ${expr.runtimeType}',
      _span(expr),
    );
  }

  PropertyValue _convertConstructorPropertyValue(_CallInfo call) {
    if (call.className == 'EdgeInsets' && call.namedConstructor == 'all') {
      return _edgeInsetsAll(call);
    }
    if (call.className == 'Color' && call.namedConstructor == null) {
      return _colorLiteral(call);
    }
    final ctorSuffix =
        call.namedConstructor == null ? '' : '.${call.namedConstructor}';
    throw ParseException(
      'Unsupported constructor value: ${call.className}$ctorSuffix',
      call.span,
    );
  }

  PropertyValue _edgeInsetsAll(_CallInfo call) {
    final args = call.argumentList.arguments;
    if (args.length != 1) {
      throw ParseException(
        'EdgeInsets.all expects exactly 1 argument; got ${args.length}',
        call.span,
      );
    }
    final arg = args.first;
    if (arg is IntegerLiteral) {
      final value = arg.value;
      if (value == null) {
        throw ParseException(
          'EdgeInsets.all argument out of range',
          _span(arg),
        );
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
    throw ParseException(
      'EdgeInsets.all argument must be a num literal',
      _span(arg),
    );
  }

  PropertyValue _colorLiteral(_CallInfo call) {
    final args = call.argumentList.arguments;
    if (args.length != 1) {
      throw ParseException(
        'Color expects exactly 1 argument; got ${args.length}',
        call.span,
      );
    }
    final arg = args.first;
    if (arg is! IntegerLiteral) {
      throw ParseException(
        'Color argument must be an integer literal',
        _span(arg),
      );
    }
    final value = arg.value;
    if (value == null) {
      throw ParseException(
        'Color argument out of range',
        _span(arg),
      );
    }
    return ColorValue(argbValue: value, span: call.span);
  }

  StyleHints _hintsFromCall(_CallInfo call) {
    final kw = call.keyword?.keyword;
    final rightParen = call.argumentList.rightParenthesis;
    final prev = rightParen.previous;
    final hasTrailingComma = prev != null && prev.lexeme == ',';
    return StyleHints(
      hasConst: kw == Keyword.CONST,
      hasNew: kw == Keyword.NEW,
      hasTrailingComma: hasTrailingComma,
    );
  }

  SourceSpan _span(SyntacticEntity entity) =>
      SourceSpan(offset: entity.offset, length: entity.length);

  /// Normalizes the two AST shapes a constructor-call-without-resolution can
  /// take: `InstanceCreationExpression` when `const`/`new` is present, else
  /// `MethodInvocation`. Returns null for anything else.
  _CallInfo? _tryExtractCall(Expression expr) {
    if (expr is InstanceCreationExpression) {
      return _CallInfo(
        className: expr.constructorName.type.name2.lexeme,
        namedConstructor: expr.constructorName.name?.name,
        argumentList: expr.argumentList,
        keyword: expr.keyword,
        span: _span(expr),
      );
    }
    if (expr is MethodInvocation) {
      final target = expr.target;
      if (target == null) {
        return _CallInfo(
          className: expr.methodName.name,
          namedConstructor: null,
          argumentList: expr.argumentList,
          keyword: null,
          span: _span(expr),
        );
      }
      if (target is SimpleIdentifier) {
        return _CallInfo(
          className: target.name,
          namedConstructor: expr.methodName.name,
          argumentList: expr.argumentList,
          keyword: null,
          span: _span(expr),
        );
      }
    }
    return null;
  }
}

class _CallInfo {
  _CallInfo({
    required this.className,
    required this.namedConstructor,
    required this.argumentList,
    required this.keyword,
    required this.span,
  });

  final String className;
  final String? namedConstructor;
  final ArgumentList argumentList;
  final Token? keyword;
  final SourceSpan span;
}
