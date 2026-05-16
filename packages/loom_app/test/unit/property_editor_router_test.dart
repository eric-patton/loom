import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loom_app/src/services/kernel_adapter.dart';
import 'package:loom_app/src/inspectors/bool_property_editor.dart';
import 'package:loom_app/src/inspectors/num_property_editor.dart';
import 'package:loom_app/src/inspectors/opaque_property_readout.dart';
import 'package:loom_app/src/inspectors/property_editor_router.dart';
import 'package:loom_app/src/inspectors/string_property_editor.dart';

import '../helpers/kernel_fixtures.dart';

void main() {
  Future<void> pumpRouter(WidgetTester tester, PropertyValue value) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: PropertyEditorRouter(
              documentUri: 'file://test.dart',
              nodePath: const <NodePathSegment>[],
              propertyName: 'data',
              propertyValue: value,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('routes StringLiteralValue → StringPropertyEditor',
      (tester) async {
    await pumpRouter(tester, stringValue('hi'));
    expect(find.byType(StringPropertyEditor), findsOneWidget);
  });

  testWidgets('routes NumLiteralValue (int) → NumPropertyEditor',
      (tester) async {
    await pumpRouter(tester, intValue(8));
    expect(find.byType(NumPropertyEditor), findsOneWidget);
  });

  testWidgets('routes NumLiteralValue (double) → NumPropertyEditor',
      (tester) async {
    await pumpRouter(tester, doubleValue(8.5));
    expect(find.byType(NumPropertyEditor), findsOneWidget);
  });

  testWidgets('routes BoolLiteralValue → BoolPropertyEditor', (tester) async {
    await pumpRouter(tester, boolValue(true));
    expect(find.byType(BoolPropertyEditor), findsOneWidget);
  });

  testWidgets('routes EdgeInsetsAllValue → OpaquePropertyReadout',
      (tester) async {
    await pumpRouter(
      tester,
      const EdgeInsetsAllValue(
        amount: 8,
        amountIsDouble: false,
        span: SourceSpan(offset: 0, length: 16),
      ),
    );
    expect(find.byType(OpaquePropertyReadout), findsOneWidget);
  });

  testWidgets('routes OpaquePropertyValue → OpaquePropertyReadout',
      (tester) async {
    await pumpRouter(tester, opaqueValue('() {}'));
    expect(find.byType(OpaquePropertyReadout), findsOneWidget);
  });

  testWidgets('routes NullLiteralValue → OpaquePropertyReadout',
      (tester) async {
    await pumpRouter(tester, nullValue());
    expect(find.byType(OpaquePropertyReadout), findsOneWidget);
  });
}
