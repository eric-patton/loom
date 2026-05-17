import 'package:flutter_test/flutter_test.dart';
import 'package:loom_app/src/services/format_service.dart';

void main() {
  group('FormatService.tryFormat', () {
    final service = FormatService();

    test('formats valid Dart and returns a non-null result', () {
      const input = 'void main(){print(  "hi"  );}';
      final result = service.tryFormat(input);
      expect(result, isNotNull);
      expect(result, contains('"hi"'));
      // Whitespace collapses; formatted output is multi-line.
      expect(result, contains('\n'));
      expect(result, isNot(equals(input)));
    });

    test('returns null when the source has a syntax error', () {
      const input = 'void main() { this is not dart }';
      expect(service.tryFormat(input), isNull);
    });

    test('idempotent on already-formatted source', () {
      const input = 'void main() {\n  print(\'hi\');\n}\n';
      final once = service.tryFormat(input);
      expect(once, isNotNull);
      final twice = service.tryFormat(once!);
      expect(twice, once);
    });
  });
}
