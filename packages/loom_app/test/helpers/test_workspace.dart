import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loom_app/src/state/providers.dart';
import 'package:path/path.dart' as p;

/// One running test session against a copy of the M11 fixture: the
/// fixture lives in a temp directory so tests can commit edits
/// without dirtying the repo, and a fully-wired `ProviderContainer`
/// drives the same providers the editor uses at runtime.
class FixtureSession {
  FixtureSession({required this.rootPath, required this.container});

  /// Path to the temp directory holding a fresh copy of the M11
  /// fixture.
  final String rootPath;

  /// Fully-wired Riverpod container with the project already loaded.
  final ProviderContainer container;

  String get counterDiskPath => p.canonicalize(
        p.join(rootPath, 'lib', 'widgets', 'counter.dart'),
      );

  String get counterUri => Uri.file(counterDiskPath).toString();

  String get mainDiskPath =>
      p.canonicalize(p.join(rootPath, 'lib', 'main.dart'));

  String get mainUri => Uri.file(mainDiskPath).toString();

  Future<String> readCounterSource() => File(counterDiskPath).readAsString();

  Future<void> dispose() async {
    container.dispose();
    try {
      Directory(rootPath).deleteSync(recursive: true);
    } on FileSystemException {
      // Best-effort cleanup; Windows occasionally holds the directory
      // for a moment after dispose. A failed cleanup leaks a temp
      // directory but does not break the run.
    }
  }
}

/// Copies `test/fixtures/m11_counter_app/` into a fresh temp directory
/// and returns the destination path. Each call yields a new copy so
/// concurrent tests don't collide.
Future<String> copyM11Fixture() async {
  final fixture = Directory(p.normalize('test/fixtures/m11_counter_app'));
  if (!fixture.existsSync()) {
    throw StateError(
      'Fixture not found at ${fixture.path}. Tests must run from '
      'packages/loom_app/ (flutter test does this automatically).',
    );
  }
  final tmp = Directory.systemTemp.createTempSync('loom_m11_');
  for (final entity in fixture.listSync(recursive: true)) {
    if (entity is! File) continue;
    final rel = p.relative(entity.path, from: fixture.path);
    // Skip `.dart_tool/` — it's machine-local cache (Loom session,
    // package config, build artifacts). If a previous in-app run
    // populated it, copying would pre-open tabs in tests and corrupt
    // their initial state.
    if (p.split(rel).contains('.dart_tool')) continue;
    final target = File(p.join(tmp.path, rel));
    target.parent.createSync(recursive: true);
    target.writeAsStringSync(entity.readAsStringSync());
  }
  return tmp.path;
}

/// Spins up a session: copies the fixture, builds a container, calls
/// `openProject` on the workspace controller. Returns when the project
/// model is fully wired.
///
/// Use [openFixtureSessionForWidgets] from inside `testWidgets`. The
/// fake-async zone that `testWidgets` installs swallows real
/// `Directory.list()` futures, so any I/O has to land inside
/// `tester.runAsync`.
Future<FixtureSession> openFixtureSession() async {
  final root = await copyM11Fixture();
  final container = ProviderContainer();
  await container.read(workspaceControllerProvider).openProject(root);
  return FixtureSession(rootPath: root, container: container);
}

/// `testWidgets`-safe variant of [openFixtureSession]. Wraps the
/// disk-touching open call in [tester.runAsync] so the fake-async
/// zone doesn't strand the real `Future`.
Future<FixtureSession> openFixtureSessionForWidgets(WidgetTester tester) async {
  final session = await tester.runAsync(openFixtureSession);
  if (session == null) {
    throw StateError('openFixtureSession returned null inside runAsync');
  }
  return session;
}
