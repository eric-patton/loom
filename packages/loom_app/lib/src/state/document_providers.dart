import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/kernel_adapter.dart';
import '../services/session_persistence_service.dart';
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

/// True iff the active document has at least one undoable edit. Watched
/// by the keyboard-shortcut layer and tab-strip tooltips.
final canUndoActiveProvider = Provider<bool>((ref) {
  final uri = ref.watch(activeDocumentUriProvider);
  if (uri == null) return false;
  return ref.watch(editHistoryProvider)[uri]?.canUndo ?? false;
});

/// True iff the active document has at least one redoable edit.
final canRedoActiveProvider = Provider<bool>((ref) {
  final uri = ref.watch(activeDocumentUriProvider);
  if (uri == null) return false;
  return ref.watch(editHistoryProvider)[uri]?.canRedo ?? false;
});

/// Orchestrates the project / documents / selection providers as a
/// single cohesive surface. The shell calls into this controller for
/// every top-level workspace action — opening a project, opening a
/// file, committing a property edit, undo/redo. Keeps the file-system
/// + kernel + notifier wiring out of the widget tree.
class WorkspaceController {
  WorkspaceController(this._ref);

  final Ref _ref;

  /// Loads the project at [rootPath], resets tab/selection/history
  /// state, and attempts to restore any persisted session.
  Future<void> openProject(String rootPath) async {
    await _ref.read(projectControllerProvider.notifier).openProject(rootPath);
    _ref.read(openDocumentsProvider.notifier).reset();
    _ref.read(activeDocumentUriProvider.notifier).state = null;
    _ref.read(selectedNodeProvider.notifier).state = null;
    _ref.read(editHistoryProvider.notifier).clearAll();
    await _restoreSession(rootPath);
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
    _ref.read(selectedNodeProvider.notifier).state = null;
    _persistSession();
  }

  /// Closes the tab for [uri] and falls back to another open tab (or
  /// null if none remain). The close-with-prompt dialog (when the doc
  /// has uncommitted state) is wired in the UI layer; this method
  /// performs the close unconditionally — callers prompt first.
  void closeFile(String uri) {
    _ref.read(openDocumentsProvider.notifier).close(uri);
    _ref.read(editHistoryProvider.notifier).clear(uri);
    if (_ref.read(activeDocumentUriProvider) == uri) {
      final remaining = _ref.read(openDocumentsProvider).keys.toList();
      _ref.read(activeDocumentUriProvider.notifier).state =
          remaining.isEmpty ? null : remaining.last;
      _ref.read(selectedNodeProvider.notifier).state = null;
    }
    _persistSession();
  }

  /// Plans a property edit through the kernel, optionally runs the
  /// per-document formatter, saves to disk, re-reads, and pushes the
  /// new content into both the open-document and project source maps
  /// so every downstream provider rebuilds. Returns true if the edit
  /// applied and persisted; false if the document wasn't open, the
  /// kernel rejected the planned edit, or the save failed.
  Future<bool> applyPropertyEdit({
    required String uri,
    required PropertyValue oldValue,
    required PropertyValue newValue,
  }) async {
    final docs = _ref.read(openDocumentsProvider);
    final doc = docs[uri];
    if (doc == null) return false;
    final before = doc.workingSource;
    final adapter = _ref.read(kernelAdapterProvider);
    final String afterEdit;
    try {
      afterEdit = adapter.applyPropertyEdit(
        source: before,
        oldValue: oldValue,
        newValue: newValue,
      );
    } on Object {
      return false;
    }
    final toSave = _maybeFormat(uri, afterEdit);
    final saved = await _writeAndReread(
        uri: uri, pathOnDisk: doc.pathOnDisk, contents: toSave);
    if (saved == null) return false;
    _ref.read(editHistoryProvider.notifier).record(
          uri: uri,
          label: 'Edit ${oldValue.runtimeType}',
          beforeSource: before,
          afterSource: saved,
        );
    return true;
  }

  /// Pops the most recent edit on the active document (or the document
  /// at [uri] if provided) and restores its pre-edit source. Returns
  /// true on success.
  Future<bool> undo([String? uri]) async {
    final target = uri ?? _ref.read(activeDocumentUriProvider);
    if (target == null) return false;
    final entry = _ref.read(editHistoryProvider.notifier).popUndo(target);
    if (entry == null) return false;
    return _restoreSource(target, entry.beforeSource);
  }

  /// Inverse of [undo]: re-applies the most recently undone edit.
  Future<bool> redo([String? uri]) async {
    final target = uri ?? _ref.read(activeDocumentUriProvider);
    if (target == null) return false;
    final entry = _ref.read(editHistoryProvider.notifier).popRedo(target);
    if (entry == null) return false;
    return _restoreSource(target, entry.afterSource);
  }

  String _maybeFormat(String uri, String source) {
    final enabled = _ref.read(formatOnSaveProvider.notifier).get(uri);
    if (!enabled) return source;
    final formatted = _ref.read(formatServiceProvider).tryFormat(source);
    return formatted ?? source;
  }

  Future<bool> _restoreSource(String uri, String source) async {
    final docs = _ref.read(openDocumentsProvider);
    final doc = docs[uri];
    if (doc == null) return false;
    final saved = await _writeAndReread(
      uri: uri,
      pathOnDisk: doc.pathOnDisk,
      contents: source,
    );
    return saved != null;
  }

  Future<String?> _writeAndReread({
    required String uri,
    required String pathOnDisk,
    required String contents,
  }) async {
    final fs = _ref.read(fileSystemServiceProvider);
    try {
      _ref.read(openDocumentsProvider.notifier).updateWorking(uri, contents);
      await fs.saveAtomic(pathOnDisk, contents);
      final reread = await fs.readFile(pathOnDisk);
      _ref.read(openDocumentsProvider.notifier).markSaved(uri, reread);
      _ref.read(projectControllerProvider.notifier).updateSource(uri, reread);
      return reread;
    } on Object {
      return null;
    }
  }

  /// Snapshots open tabs + active tab to `<root>/.dart_tool/loom/session.json`.
  /// Best-effort — failures never surface as errors.
  void _persistSession() {
    final ps = _ref.read(projectControllerProvider);
    if (ps == null) return;
    final root = ps.snapshot.rootPath;
    final svc = _ref.read(sessionPersistenceServiceProvider);
    final docs = _ref.read(openDocumentsProvider);
    final active = _ref.read(activeDocumentUriProvider);
    final relPaths = <String>[
      for (final uri in docs.keys)
        if (svc.uriToRelative(uri, root) case final String r) r,
    ];
    final activeRel = active == null ? null : svc.uriToRelative(active, root);
    unawaited(svc.save(
      root,
      SavedSession(
        openRelativePaths: relPaths,
        activeRelativePath: activeRel,
      ),
    ));
  }

  Future<void> _restoreSession(String rootPath) async {
    final svc = _ref.read(sessionPersistenceServiceProvider);
    final saved = await svc.tryLoad(rootPath);
    if (saved == null) return;
    final ps = _ref.read(projectControllerProvider);
    if (ps == null) return;
    for (final rel in saved.openRelativePaths) {
      final uri = svc.relativeToUri(rel, rootPath);
      if (ps.sources.containsKey(uri)) openFile(uri);
    }
    if (saved.activeRelativePath != null) {
      final activeUri = svc.relativeToUri(saved.activeRelativePath!, rootPath);
      if (ps.sources.containsKey(activeUri)) {
        _ref.read(activeDocumentUriProvider.notifier).state = activeUri;
      }
    }
  }
}

final workspaceControllerProvider = Provider<WorkspaceController>(
  WorkspaceController.new,
);
