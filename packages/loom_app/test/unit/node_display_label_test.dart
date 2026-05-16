import 'package:flutter_test/flutter_test.dart';
import 'package:loom_app/src/services/kernel_adapter.dart';
import 'package:loom_app/src/surfaces/widget_outline/node_display_label.dart';

import '../helpers/kernel_fixtures.dart';

void main() {
  test('WidgetNode (unnamed) → className', () {
    final n = widgetNode(className: 'Column');
    expect(NodeDisplayLabel.labelFor(n), 'Column');
  });

  test('WidgetNode (named ctor) → className.namedCtor', () {
    final n = widgetNode(
      className: 'MaterialApp',
      namedConstructor: 'router',
    );
    expect(NodeDisplayLabel.labelFor(n), 'MaterialApp.router');
  });

  test('OpaqueNode → « opaque »', () {
    expect(
      NodeDisplayLabel.labelFor(opaqueNode('ternary ? a : b')),
      '« opaque »',
    );
  });

  test('MethodReferenceNode → method <name>()', () {
    final mref = MethodReferenceNode(
      methodName: '_buildHeader',
      callSourceSpan: const SourceSpan(offset: 0, length: 14),
      body: widgetNode(className: 'SizedBox'),
    );
    expect(NodeDisplayLabel.labelFor(mref), 'method _buildHeader()');
  });
}
