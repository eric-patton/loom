import 'package:flutter_test/flutter_test.dart';
import 'package:loom_app/src/services/kernel_adapter.dart';
import 'package:loom_app/src/surfaces/widget_canvas/canvas_node_label.dart';

import '../helpers/kernel_fixtures.dart';

void main() {
  test('Text with a StringLiteralValue data shows truncated content', () {
    final node = widgetNode(
      className: 'Text',
      properties: <String, PropertyValue>{
        'data': stringValue('Hello'),
      },
    );
    expect(canvasLabelFor(node), "Text 'Hello'");
  });

  test('Text with long content is truncated with an ellipsis', () {
    final node = widgetNode(
      className: 'Text',
      properties: <String, PropertyValue>{
        'data': stringValue('This is a very long piece of text'),
      },
    );
    final label = canvasLabelFor(node);
    expect(label, startsWith("Text 'This is a very "));
    expect(label, endsWith("…'"));
  });

  test('SizedBox renders dimensions when both width and height present', () {
    final node = widgetNode(
      className: 'SizedBox',
      properties: <String, PropertyValue>{
        'width': intValue(100),
        'height': intValue(50),
      },
    );
    expect(canvasLabelFor(node), 'SizedBox 100×50');
  });

  test('Padding shows the EdgeInsets.all amount', () {
    final node = widgetNode(
      className: 'Padding',
      properties: <String, PropertyValue>{
        'padding': const EdgeInsetsAllValue(
          amount: 8,
          amountIsDouble: false,
          span: SourceSpan(offset: 0, length: 16),
        ),
      },
    );
    expect(canvasLabelFor(node), 'Padding 8');
  });

  test('Visibility renders ✓ / ✗ based on the visible bool', () {
    expect(
      canvasLabelFor(widgetNode(
        className: 'Visibility',
        properties: <String, PropertyValue>{'visible': boolValue(true)},
      )),
      'Visibility ✓',
    );
    expect(
      canvasLabelFor(widgetNode(
        className: 'Visibility',
        properties: <String, PropertyValue>{'visible': boolValue(false)},
      )),
      'Visibility ✗',
    );
  });

  test('falls back to the outline label for opaque nodes', () {
    expect(canvasLabelFor(opaqueNode('foo')), '« opaque »');
  });

  test('falls back to className for widgets without enriched info', () {
    expect(canvasLabelFor(widgetNode(className: 'Center')), 'Center');
  });
}
