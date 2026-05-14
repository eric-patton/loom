import 'source_span.dart';

/// A literal property value attached to a `WidgetNode`'s named argument.
///
/// The variants below cover the M1 surface listed in PROJECT_SPEC.md:
/// strings, numbers, booleans, null, `EdgeInsets.all(N)`, simple
/// `Color(0x...)` constructors, and basic prefixed identifiers like
/// `MainAxisAlignment.center` / `Colors.blue` / `Icons.menu`. Anything
/// outside this set is outside M1's modeling scope and will throw at
/// parse time until M4's opaque fallback lands.
sealed class PropertyValue {
  const PropertyValue({required this.span});

  /// Byte range of the value expression in the source (excluding the
  /// `name:` label of the enclosing `NamedExpression`).
  final SourceSpan span;
}

class StringLiteralValue extends PropertyValue {
  const StringLiteralValue({
    required this.value,
    required super.span,
    this.usesDoubleQuotes = false,
  });

  /// Decoded string content (escape sequences resolved).
  final String value;

  /// `true` if the source used `"..."`, `false` for `'...'`. Preserved
  /// for byte-faithful emission. Raw strings (`r'...'`) and triple-quoted
  /// strings are not represented by this class — they round-trip as
  /// `OpaquePropertyValue`.
  final bool usesDoubleQuotes;

  @override
  bool operator ==(Object other) =>
      other is StringLiteralValue &&
      other.value == value &&
      other.usesDoubleQuotes == usesDoubleQuotes &&
      other.span == span;

  @override
  int get hashCode => Object.hash(value, usesDoubleQuotes, span);

  @override
  String toString() {
    final q = usesDoubleQuotes ? '"' : "'";
    return 'StringLiteralValue($q$value$q)';
  }
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

class BoolLiteralValue extends PropertyValue {
  const BoolLiteralValue({required this.value, required super.span});

  final bool value;

  @override
  bool operator ==(Object other) =>
      other is BoolLiteralValue && other.value == value && other.span == span;

  @override
  int get hashCode => Object.hash(value, span);

  @override
  String toString() => 'BoolLiteralValue($value)';
}

class NullLiteralValue extends PropertyValue {
  const NullLiteralValue({required super.span});

  @override
  bool operator ==(Object other) =>
      other is NullLiteralValue && other.span == span;

  @override
  int get hashCode => span.hashCode;

  @override
  String toString() => 'NullLiteralValue';
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

class ColorValue extends PropertyValue {
  const ColorValue({required this.argbValue, required super.span});

  /// The integer argument to `Color(...)`, typically a 32-bit ARGB hex
  /// literal (e.g. `0xFF000000`). We don't normalize to a Color object —
  /// we preserve the user's integer for byte-faithful re-emission.
  final int argbValue;

  @override
  bool operator ==(Object other) =>
      other is ColorValue && other.argbValue == argbValue && other.span == span;

  @override
  int get hashCode => Object.hash(argbValue, span);

  @override
  String toString() =>
      'ColorValue(0x${argbValue.toRadixString(16).padLeft(8, '0').toUpperCase()})';
}

/// An unmodelable property value, captured verbatim. Introduced in M4.
/// Carries `sourceText` so equivalence comparison after re-parse (which
/// shifts spans) still has a stable identity. Emission re-uses these
/// bytes; the kernel API offers no mutation on this variant.
class OpaquePropertyValue extends PropertyValue {
  const OpaquePropertyValue({required super.span, required this.sourceText});

  final String sourceText;

  @override
  bool operator ==(Object other) =>
      other is OpaquePropertyValue && other.sourceText == sourceText;

  @override
  int get hashCode => sourceText.hashCode;

  @override
  String toString() {
    final preview = sourceText.length > 30
        ? '${sourceText.substring(0, 30)}...'
        : sourceText;
    return 'OpaquePropertyValue("${preview.replaceAll('\n', '\\n')}")';
  }
}

/// A `Prefix.member` reference — captures both true enum references
/// (`MainAxisAlignment.center`) and static-field references that share
/// the same syntactic shape (`Colors.blue`, `Icons.menu`,
/// `TextDirection.ltr`). M1 makes no semantic distinction; both round-trip
/// identically as `Prefix.member`.
class EnumReferenceValue extends PropertyValue {
  const EnumReferenceValue({
    required this.typeName,
    required this.memberName,
    required super.span,
  });

  final String typeName;
  final String memberName;

  @override
  bool operator ==(Object other) =>
      other is EnumReferenceValue &&
      other.typeName == typeName &&
      other.memberName == memberName &&
      other.span == span;

  @override
  int get hashCode => Object.hash(typeName, memberName, span);

  @override
  String toString() => 'EnumReferenceValue($typeName.$memberName)';
}
