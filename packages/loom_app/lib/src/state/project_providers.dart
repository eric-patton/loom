import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/file_system_service.dart';
import '../services/kernel_adapter.dart';
import 'kernel_providers.dart';

/// The currently-open project: the disk snapshot that bootstrapped the
/// session plus the live source map, which diverges from the snapshot
/// as the user commits property edits. The kernel rebuilds against the
/// live map.
class ProjectState {
  const ProjectState({required this.snapshot, required this.sources});

  final ProjectSnapshot snapshot;

  /// Live `{uri → source}` map. Equal to `snapshot.sources` immediately
  /// after load; diverges as commits land.
  final Map<String, String> sources;

  ProjectState withSources(Map<String, String> next) =>
      ProjectState(snapshot: snapshot, sources: next);
}

class ProjectController extends Notifier<ProjectState?> {
  @override
  ProjectState? build() => null;

  /// Walks [rootPath], reads every `.dart` file, and sets the project
  /// state to the resulting snapshot. The kernel model rebuilds via the
  /// derived [projectModelProvider].
  Future<void> openProject(String rootPath) async {
    final fs = ref.read(fileSystemServiceProvider);
    final snap = await fs.readProject(rootPath);
    state = ProjectState(snapshot: snap, sources: snap.sources);
  }

  /// Replaces the source for [uri] in the live map. Called from the
  /// save pipeline after a successful atomic write so the kernel index
  /// rebuilds against the new content.
  void updateSource(String uri, String newSource) {
    final current = state;
    if (current == null) return;
    state = current.withSources(<String, String>{
      ...current.sources,
      uri: newSource,
    });
  }

  /// Clears the project. Used by tests and by the "close project"
  /// action (not yet exposed in the M11 UI).
  void clear() {
    state = null;
  }
}

final projectControllerProvider =
    NotifierProvider<ProjectController, ProjectState?>(
  ProjectController.new,
);

/// The kernel `ProjectModel` derived from the live source map. Null when
/// no project is open.
final projectModelProvider = Provider<ProjectModel?>((ref) {
  final ps = ref.watch(projectControllerProvider);
  if (ps == null) return null;
  return ref.read(kernelAdapterProvider).buildProject(ps.sources);
});

/// Cross-file widget index for the current project. Null when no
/// project is open. Rebuilds whenever the source map changes — the
/// expense is acceptable in M11 (single-digit-ms for the M11 fixture)
/// and a future milestone can introduce incremental indexing.
final projectWidgetIndexProvider = Provider<ProjectWidgetIndex?>((ref) {
  final model = ref.watch(projectModelProvider);
  if (model == null) return null;
  return ref.read(kernelAdapterProvider).buildWidgetIndex(model);
});
