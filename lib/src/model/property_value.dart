import 'source_span.dart';

/// A literal property value attached to a `WidgetNode`'s named argument.
///
/// The variants below cover what the M1 fixture needs. New fixtures (and
/// the corpus-expansion follow-up plan) will grow this set — Color,
/// EnumReference, EdgeInsets shapes beyond `.all`, etc. Anything outside the
/// supported set is outside M1's modeling scope.
sealed class PropertyValue {
  const PropertyValue({required this.span});

  /// Byte range of the value expression in the source (excluding the
  /// `name:` label of the enclosing `NamedExpression`).
  final SourceSpan span;
}

class StringLiteralValue extends PropertyValue {
  const StringLiteralValue({required this.value, required super.span});

  final String value;

  @override
  bool operator ==(Object other) =>
      other is StringLiteralValue && other.value == value && other.span == span;

  @override
  int get hashCode => Object.hash(value, span);

  @override
  String toString() => "StringLiteralValue('$value')";
}

class NumLiteralValue extends PropertyValue {
  const NumLiteralValue({
    required this.value,
    required this.isDouble,
    required super.span,
  });

  final num value;

  /// `true` if the source wrote a double literal (e.g. `8.0`), `false` if an
  /// integer literal (`8`). Same arithmetic value, different glyphs — and the
  /// glyphs matter for round-trip fidelity.
  final bool isDouble;

  @override
  bool operator ==(Object other) =>
      other is NumLiteralValue &&
      other.value == value &&
      other.isDouble == isDouble &&
      other.span == span;

  @override
  int get hashCode => Object.hash(value, isDouble, span);

  @override
  String toString() =>
      'NumLiteralValue($value${isDouble ? ' (double)' : ' (int)'})';
}

class EdgeInsetsAllValue extends PropertyValue {
  const EdgeInsetsAllValue({
    required this.amount,
    required this.amountIsDouble,
    required super.span,
  });

  final num amount;
  final bool amountIsDouble;

  @override
  bool operator ==(Object other) =>
      other is EdgeInsetsAllValue &&
      other.amount == amount &&
      other.amountIsDouble == amountIsDouble &&
      other.span == span;

  @override
  int get hashCode => Object.hash(amount, amountIsDouble, span);

  @override
  String toString() => 'EdgeInsetsAllValue($amount)';
}
