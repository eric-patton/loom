import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loom_app/src/services/kernel_adapter.dart';
import 'package:loom_app/src/surfaces/widget_canvas/materializer/property_resolver.dart';

import '../helpers/kernel_fixtures.dart';

/// Unit tests for PropertyResolver — the pure-converter layer that
/// turns kernel PropertyValue subtypes into Dart primitives ready to
/// feed Flutter widget constructors.
void main() {
  const resolver = PropertyResolver();

  group('string', () {
    test('returns value for StringLiteralValue', () {
      expect(resolver.string(stringValue('hi')), equals('hi'));
    });
    test('returns null for non-string values', () {
      expect(resolver.string(intValue(7)), isNull);
      expect(resolver.string(opaqueValue('foo()')), isNull);
      expect(resolver.string(null), isNull);
    });
  });

  group('doubleOf', () {
    test('returns double for NumLiteralValue (int or double)', () {
      expect(resolver.doubleOf(intValue(8)), equals(8.0));
      expect(resolver.doubleOf(doubleValue(3.5)), equals(3.5));
    });
    test('returns null for non-num values', () {
      expect(resolver.doubleOf(stringValue('hi')), isNull);
      expect(resolver.doubleOf(opaqueValue('foo')), isNull);
      expect(resolver.doubleOf(null), isNull);
    });
  });

  group('boolean', () {
    test('returns bool for BoolLiteralValue', () {
      expect(resolver.boolean(boolValue(true)), isTrue);
      expect(resolver.boolean(boolValue(false)), isFalse);
    });
    test('returns null for non-bool values', () {
      expect(resolver.boolean(intValue(1)), isNull);
      expect(resolver.boolean(opaqueValue('!x')), isNull);
    });
  });

  group('color', () {
    test('returns Color for ColorValue', () {
      final color = resolver.color(ColorValue(
        argbValue: 0xFFFF0000,
        span: const SourceSpan(offset: 0, length: 10),
      ));
      expect(color, isA<Color>());
      expect(color!.toARGB32(), equals(0xFFFF0000));
    });
    test('returns null for non-color values', () {
      expect(resolver.color(stringValue('red')), isNull);
      expect(resolver.color(opaqueValue('Colors.red')), isNull);
    });
  });

  group('edgeInsets', () {
    test('returns EdgeInsets.all for EdgeInsetsAllValue', () {
      final ei = resolver.edgeInsets(EdgeInsetsAllValue(
        amount: 8.0,
        amountIsDouble: true,
        span: const SourceSpan(offset: 0, length: 10),
      ));
      expect(ei, equals(const EdgeInsets.all(8)));
    });
    test('returns null for non-edge-insets values', () {
      expect(resolver.edgeInsets(intValue(8)), isNull);
      expect(
          resolver.edgeInsets(opaqueValue('EdgeInsets.fromLTRB(...)')), isNull);
    });
  });

  group('enumValue', () {
    test('returns mapped enum for EnumReferenceValue', () {
      const lookup = <String, Alignment>{
        'center': Alignment.center,
        'topLeft': Alignment.topLeft,
      };
      expect(
        resolver.enumValue(enumRef('Alignment', 'center'), lookup),
        equals(Alignment.center),
      );
    });
    test('returns null when memberName not in lookup', () {
      const lookup = <String, Alignment>{'center': Alignment.center};
      expect(
        resolver.enumValue(enumRef('Alignment', 'unknown'), lookup),
        isNull,
      );
    });
    test('returns null for non-enum values', () {
      const lookup = <String, Alignment>{'center': Alignment.center};
      expect(resolver.enumValue(stringValue('center'), lookup), isNull);
    });
  });

  group('OpaquePropertyValue', () {
    test('every typed accessor falls back to null', () {
      final opaque = opaqueValue('myVar');
      expect(resolver.string(opaque), isNull);
      expect(resolver.doubleOf(opaque), isNull);
      expect(resolver.boolean(opaque), isNull);
      expect(resolver.color(opaque), isNull);
      expect(resolver.edgeInsets(opaque), isNull);
      expect(
        resolver.enumValue(opaque, const <String, Alignment>{}),
        isNull,
      );
    });
  });
}
