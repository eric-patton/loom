import '../model/property_value.dart';

/// Converts a `PropertyValue` to the Dart source string that will re-parse
/// to an equivalent value.
///
/// Conventions (M2):
///   - Strings are single-quoted with internal `'` and `\` escaped.
///     Quote style is not preserved across edits — see DEVLOG if a fixture
///     ever introduces double quotes.
///   - `isDouble` is honored: a `NumLiteralValue` with `isDouble: true`
///     always emits a `.` in its literal, even when the arithmetic value
///     is integral (`8` becomes `8.0`).
///   - `Color(0xFFXXXXXX)` uses 8 upper-case hex digits.
///   - Enum references re-emit literally as `Prefix.member`.
class PropertySerializer {
  PropertySerializer._();

  static String serialize(PropertyValue value) => switch (value) {
        StringLiteralValue(value: final s) => "'${_escapeString(s)}'",
        NumLiteralValue(value: final n, isDouble: final isD) => _formatNum(
            n,
            isDouble: isD,
          ),
        BoolLiteralValue(value: final b) => b ? 'true' : 'false',
        NullLiteralValue() => 'null',
        EdgeInsetsAllValue(amount: final a, amountIsDouble: final isD) =>
          'EdgeInsets.all(${_formatNum(a, isDouble: isD)})',
        ColorValue(argbValue: final v) =>
          'Color(0x${v.toRadixString(16).padLeft(8, '0').toUpperCase()})',
        EnumReferenceValue(typeName: final t, memberName: final m) => '$t.$m',
      };

  static String _escapeString(String s) =>
      s.replaceAll(r'\', r'\\').replaceAll("'", r"\'");

  static String _formatNum(num value, {required bool isDouble}) {
    if (!isDouble) {
      return value.toInt().toString();
    }
    final s = value.toString();
    return s.contains('.') ? s : '$s.0';
  }
}
