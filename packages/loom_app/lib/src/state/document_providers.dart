import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/kernel_adapter.dart';
import 'kernel_providers.dart';
import 'models/open_document.dart';
import 'notifiers/open_documents_notifier.dart';
import 'project_providers.dart';
import 'selection_providers.dart';

/// `{uri → OpenDocument}` for every tab the user has open.
final openDocumentsProvider =
    NotifierProvider<OpenDocumentsNotifier, Map<String, OpenDocument>>(
  OpenDocumentsNotifier.new,
);

/// URI of the focused tab, or null when no tab is open.
final activeDocumentUriProvider = StateProvider<String?>((ref) => null);

/// Parsed widget tree for the document at [uri]. Rebuilds when the
/// document's working source changes or when the project widget index
/// rebuilds (e.g. another file's source changed).
final widgetTreeForDocumentProvider =
    Provider.family.autoDispose<WidgetTreeParseResult, String>((ref, uri) {
  final docs = ref.watch(openDocumentsProvider);
  final doc = docs[uri];
  if (doc == null) {
    return const WidgetTreeParseFailure('Document not open');
  }
  final adapter = ref.watch(kernelAdapterProvider);
  final index = ref.watch(projectWidgetIndexProvider);
  final visible =
      index?.widgetsVisibleFrom(uri) ?? const <String, WidgetSpec>{};
  return adapter.parseWidgetTreeFor(
    source: doc.workingSource,
    projectWidgets: visible,
  );
});

/// Orchestrates the project / documents / selection providers as a
/// single cohesive surface. The shell calls into this controller for
/// every top-level workspace action — opening a project, opening a
/// file, committing a property edit. Keeps the file-system + kernel +
/// notifier wiring out of the widget tree.
class WorkspaceController {
  WorkspaceController(this._ref);

  final Ref _ref;

  /// Loads the project at [rootPath] and resets tab/selection state.
  Future<void> openProject(String rootPath) async {
    await _ref.read(projectControllerProvider.notifier).openProject(rootPath);
    _ref.read(openDocumentsProvider.notifier).reset();
    _ref.read(activeDocumentUriProvider.notifier).state = null;
    _ref.read(selectedNodePathProvider.notifier).state = null;
  }

  /// Opens (or focuses) the tab for [uri].
  void openFile(String uri) {
    final ps = _ref.read(projectControllerProvider);
    if (ps == null) return;
    final source = ps.sources[uri];
    if (source == null) return;
    final pathOnDisk = ps.snapshot.uriToPath[uri] ?? uri;
    final docs = _ref.read(openDocumentsProvider);
    if (!docs.containsKey(uri)) {
      _ref.read(openDocumentsProvider.notifier).open(
            OpenDocument(
              uri: uri,
              pathOnDisk: pathOnDisk,
              diskSource: source,
              workingSource: source,
            ),
          );
    }
    _ref.read(activeDocumentUriProvider.notifier).state = uri;
    _ref.read(selectedNodePathProvider.notifier).state = null;
  }

  /// Closes the tab for [uri] and falls back to another open tab (or
  /// null if none remain). The dirty-prompt is M12 work; M11 commits
  /// every edit immediately, so closing never loses unsaved state.
  void closeFile(String uri) {
    _ref.read(openDocumentsProvider.notifier).close(uri);
    if (_ref.read(activeDocumentUriProvider) == uri) {
      final remaining = _ref.read(openDocumentsProvider).keys.toList();
      _ref.read(activeDocumentUriProvider.notifier).state =
          remaining.isEmpty ? null : remaining.last;
      _ref.read(selectedNodePathProvider.notifier).state = null;
    }
  }

  /// Plans a property edit through the kernel, applies the resulting
  /// `SourceEdit`, saves to disk, re-reads, and pushes the new content
  /// into both the open-document and project source maps so every
  /// downstream provider rebuilds. Returns true if the edit applied
  /// and persisted; false if the document wasn't open or the kernel
  /// rejected the planned edit.
  Future<bool> applyPropertyEdit({
    required String uri,
    required PropertyValue oldValue,
    required PropertyValue newValue,
  }) async {
    final docs = _ref.read(openDocumentsProvider);
    final doc = docs[uri];
    if (doc == null) return false;
    final adapter = _ref.read(kernelAdapterProvider);
    final String afterEdit;
    try {
      afterEdit = adapter.applyPropertyEdit(
        source: doc.workingSource,
        oldValue: oldValue,
        newValue: newValue,
      );
    } on Object {
      return false;
    }
    _ref.read(openDocumentsProvider.notifier).updateWorking(uri, afterEdit);
    final fs = _ref.read(fileSystemServiceProvider);
    await fs.saveAtomic(doc.pathOnDisk, afterEdit);
    final reread = await fs.readFile(doc.pathOnDisk);
    _ref.read(openDocumentsProvider.notifier).markSaved(uri, reread);
    _ref.read(projectControllerProvider.notifier).updateSource(uri, reread);
    return true;
  }
}

final workspaceControllerProvider = Provider<WorkspaceController>(
  WorkspaceController.new,
);
