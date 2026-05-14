import '../model/property_value.dart';

/// Converts a `PropertyValue` to the Dart source string that will re-parse
/// to an equivalent value.
///
/// Conventions:
///   - Strings preserve the source's quote style (`'…'` vs `"…"`). Raw
///     and triple-quoted forms aren't modeled by `StringLiteralValue` —
///     those land in `OpaquePropertyValue` and round-trip verbatim.
///   - String content is escaped for the chosen quote: backslash, the
///     matching quote, `$` (to prevent interpolation), and the printable
///     control escapes `\n`, `\r`, `\t`, `\b`. Other code units below
///     U+0020 emit as `\xHH`.
///   - `isDouble` is honored: `NumLiteralValue` with `isDouble: true`
///     always emits a `.` (`8` becomes `8.0`).
///   - `Color(0xFFXXXXXX)` uses 8 upper-case hex digits. Negative values
///     and values exceeding 32 bits are rejected with `ArgumentError`.
///   - `Enum references re-emit literally as `Prefix.member`.
///   - `OpaquePropertyValue` emits its captured `sourceText` verbatim.
class PropertySerializer {
  PropertySerializer._();

  static String serialize(PropertyValue value) => switch (value) {
        StringLiteralValue(
          value: final s,
          usesDoubleQuotes: final useDouble,
        ) =>
          _formatString(s, inDouble: useDouble),
        NumLiteralValue(value: final n, isDouble: final isD) => _formatNum(
            n,
            isDouble: isD,
          ),
        BoolLiteralValue(value: final b) => b ? 'true' : 'false',
        NullLiteralValue() => 'null',
        EdgeInsetsAllValue(amount: final a, amountIsDouble: final isD) =>
          'EdgeInsets.all(${_formatNum(a, isDouble: isD)})',
        ColorValue(argbValue: final v) => _formatColor(v),
        EnumReferenceValue(typeName: final t, memberName: final m) => '$t.$m',
        OpaquePropertyValue(sourceText: final t) => t,
      };

  static String _formatString(String s, {required bool inDouble}) {
    final quote = inDouble ? '"' : "'";
    final buf = StringBuffer(quote);
    for (var i = 0; i < s.length; i++) {
      final code = s.codeUnitAt(i);
      switch (code) {
        case 0x09: // tab
          buf.write(r'\t');
        case 0x0A: // newline
          buf.write(r'\n');
        case 0x0D: // carriage return
          buf.write(r'\r');
        case 0x08: // backspace
          buf.write(r'\b');
        case 0x5C: // backslash
          buf.write(r'\\');
        case 0x24: // dollar sign — escape to prevent interpolation
          buf.write(r'\$');
        case 0x27: // single quote
          if (inDouble) {
            buf.writeCharCode(code);
          } else {
            buf.write(r"\'");
          }
        case 0x22: // double quote
          if (inDouble) {
            buf.write(r'\"');
          } else {
            buf.writeCharCode(code);
          }
        default:
          if (code < 0x20 || code == 0x7F) {
            // Sub-space control bytes and DEL (0x7F): escape as `\xHH`
            // rather than emitting raw, so the output source has no
            // non-printable bytes.
            buf.write('\\x${code.toRadixString(16).padLeft(2, '0')}');
          } else {
            buf.writeCharCode(code);
          }
      }
    }
    buf.write(quote);
    return buf.toString();
  }

  static String _formatNum(num value, {required bool isDouble}) {
    if (value.isNaN) {
      throw ArgumentError.value(value, 'value', 'NaN cannot be serialized');
    }
    if (value.isInfinite) {
      throw ArgumentError.value(
        value,
        'value',
        'Infinity cannot be serialized',
      );
    }
    if (!isDouble) {
      return value.toInt().toString();
    }
    final s = value.toString();
    return s.contains('.') ? s : '$s.0';
  }

  static String _formatColor(int argbValue) {
    if (argbValue < 0) {
      throw ArgumentError.value(
        argbValue,
        'argbValue',
        'Color argbValue must be non-negative',
      );
    }
    if (argbValue > 0xFFFFFFFF) {
      throw ArgumentError.value(
        argbValue,
        'argbValue',
        'Color argbValue must fit in 32 bits',
      );
    }
    return 'Color(0x${argbValue.toRadixString(16).padLeft(8, '0').toUpperCase()})';
  }
}
