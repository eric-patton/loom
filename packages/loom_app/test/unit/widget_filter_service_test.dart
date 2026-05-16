import 'package:flutter_test/flutter_test.dart';
import 'package:loom_app/src/services/kernel_adapter.dart';
import 'package:loom_app/src/services/widget_filter_service.dart';

void main() {
  const adapter = KernelAdapter();
  const filter = WidgetFilterService(adapter);

  test('modeled root → FileWidgetRootKind.modeled', () {
    const source = '''
class Greet extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const Text('hi');
}
''';
    final classification = filter.classify(uri: 'a.dart', source: source);
    expect(classification.kind, FileWidgetRootKind.modeled);
    expect(classification.isModeled, isTrue);
  });

  test('no build() method → FileWidgetRootKind.noBuild', () {
    const source = 'void main() {}';
    final classification = filter.classify(uri: 'a.dart', source: source);
    expect(classification.kind, FileWidgetRootKind.noBuild);
  });

  test('opaque-root expression → FileWidgetRootKind.opaqueRoot', () {
    // Ternary at the root of build()'s return — visitor can't model it,
    // it lands as an OpaqueNode at the root.
    const source = '''
class Bad extends StatelessWidget {
  final bool flag = true;
  @override
  Widget build(BuildContext context) {
    return flag ? const Text('a') : const Text('b');
  }
}
''';
    final classification = filter.classify(uri: 'a.dart', source: source);
    expect(classification.kind, FileWidgetRootKind.opaqueRoot);
    expect(classification.isModeled, isFalse);
  });
}
