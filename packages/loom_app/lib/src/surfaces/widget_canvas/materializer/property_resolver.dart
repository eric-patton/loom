import 'package:flutter/widgets.dart';

import '../../../services/kernel_adapter.dart';

/// Converts kernel `PropertyValue`s into Dart primitives ready to pass
/// to Flutter widget constructors. Each accessor returns `null` for
/// unrecognized shapes — `OpaquePropertyValue` always returns null, so
/// callers fall through to their widget's constructor default. The
/// materializer never *fabricates* values for opaque properties; it
/// renders the widget with safe defaults instead.
class PropertyResolver {
  const PropertyResolver();

  String? string(PropertyValue? value) {
    if (value is StringLiteralValue) return value.value;
    return null;
  }

  double? doubleOf(PropertyValue? value) {
    if (value is NumLiteralValue) return value.value.toDouble();
    return null;
  }

  bool? boolean(PropertyValue? value) {
    if (value is BoolLiteralValue) return value.value;
    return null;
  }

  Color? color(PropertyValue? value) {
    if (value is ColorValue) return Color(value.argbValue);
    return null;
  }

  EdgeInsets? edgeInsets(PropertyValue? value) {
    if (value is EdgeInsetsAllValue) {
      return EdgeInsets.all(value.amount.toDouble());
    }
    return null;
  }

  /// Looks up an enum reference (`MainAxisAlignment.center`) in a
  /// per-property lookup table. Returns null if the value isn't an
  /// `EnumReferenceValue` or the member name isn't in [lookup].
  T? enumValue<T>(PropertyValue? value, Map<String, T> lookup) {
    if (value is! EnumReferenceValue) return null;
    return lookup[value.memberName];
  }
}
