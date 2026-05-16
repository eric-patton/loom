import 'package:flutter_test/flutter_test.dart';
import 'package:loom_app/main.dart';
import 'package:loom_app/src/shell/main_shell_screen.dart';

void main() {
  testWidgets(
    'LoomApp boots, renders the shell, and shows the empty editor state',
    (tester) async {
      await tester.pumpWidget(const LoomApp());
      await tester.pump();

      // Shell composition.
      expect(find.byType(MainShellScreen), findsOneWidget);

      // Top bar contains the app name and the File menu button.
      expect(find.text('Loom'), findsOneWidget);
      expect(find.text('File'), findsOneWidget);

      // Center editor surface invites the user to open a project.
      expect(find.textContaining('Open a project'), findsOneWidget);

      // Right pane's Interface tab notes there is no project open.
      expect(find.textContaining('No project open'), findsOneWidget);

      // Inspector idle state.
      expect(find.textContaining('Select a node'), findsOneWidget);
    },
  );
}
