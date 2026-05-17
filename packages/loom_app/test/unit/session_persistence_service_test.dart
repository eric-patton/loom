import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:loom_app/src/services/session_persistence_service.dart';
import 'package:path/path.dart' as p;

void main() {
  group('SessionPersistenceService', () {
    const svc = SessionPersistenceService();
    late Directory tempDir;

    setUp(() => tempDir = Directory.systemTemp.createTempSync('loom_session_'));
    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } on FileSystemException {
        // best-effort
      }
    });

    test('tryLoad returns null when no session file exists', () async {
      expect(await svc.tryLoad(tempDir.path), isNull);
    });

    test('save then tryLoad round-trips the open + active fields', () async {
      const session = SavedSession(
        openRelativePaths: <String>['lib/a.dart', 'lib/b.dart'],
        activeRelativePath: 'lib/a.dart',
      );
      await svc.save(tempDir.path, session);
      final loaded = await svc.tryLoad(tempDir.path);
      expect(loaded, isNotNull);
      expect(loaded!.openRelativePaths, <String>['lib/a.dart', 'lib/b.dart']);
      expect(loaded.activeRelativePath, 'lib/a.dart');
    });

    test('tryLoad returns null for malformed JSON', () async {
      final file =
          File(p.join(tempDir.path, '.dart_tool', 'loom', 'session.json'));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('{ not json');
      expect(await svc.tryLoad(tempDir.path), isNull);
    });

    test('uriToRelative converts file URIs to project-relative posix paths',
        () {
      final filePath = p.canonicalize(p.join(tempDir.path, 'lib', 'main.dart'));
      File(filePath).createSync(recursive: true);
      final uri = Uri.file(filePath).toString();
      final rel = svc.uriToRelative(uri, tempDir.path);
      expect(rel, 'lib/main.dart');
    });

    test('uriToRelative returns null when the URI is outside the project', () {
      final outside = Directory.systemTemp.createTempSync('loom_outside_');
      addTearDown(() => outside.deleteSync(recursive: true));
      final filePath = p.canonicalize(p.join(outside.path, 'a.dart'));
      File(filePath).writeAsStringSync('x');
      final uri = Uri.file(filePath).toString();
      expect(svc.uriToRelative(uri, tempDir.path), isNull);
    });

    test('relativeToUri reconstructs a canonical file:// URI', () {
      final filePath = p.canonicalize(p.join(tempDir.path, 'lib', 'main.dart'));
      File(filePath).createSync(recursive: true);
      final expected = Uri.file(filePath).toString();
      final actual = svc.relativeToUri('lib/main.dart', tempDir.path);
      expect(actual, expected);
    });

    test('save writes to .dart_tool/loom/session.json', () async {
      await svc.save(tempDir.path, SavedSession.empty);
      expect(
        File(p.join(tempDir.path, '.dart_tool', 'loom', 'session.json'))
            .existsSync(),
        isTrue,
      );
    });
  });
}
