import 'package:flutter_test/flutter_test.dart';
import 'package:loom_app/main.dart';

void main() {
  testWidgets('LoomApp boots and renders placeholder', (tester) async {
    await tester.pumpWidget(const LoomApp());
    expect(find.text('Loom — visual editor (M11 placeholder)'), findsOneWidget);
  });
}
