import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/edit_history_service.dart';
import '../services/file_system_service.dart';
import '../services/format_service.dart';
import '../services/kernel_adapter.dart';
import '../services/session_persistence_service.dart';
import '../services/widget_filter_service.dart';

/// Single instance of the kernel seam. Stateless; the `const` constructor
/// lets it live for the lifetime of the app.
final kernelAdapterProvider =
    Provider<KernelAdapter>((ref) => const KernelAdapter());

/// Stateless filesystem service. Lives as long as the app.
final fileSystemServiceProvider =
    Provider<FileSystemService>((ref) => const FileSystemService());

/// File-classification helper; depends on the kernel seam for parsing.
final widgetFilterServiceProvider = Provider<WidgetFilterService>(
  (ref) => WidgetFilterService(ref.watch(kernelAdapterProvider)),
);

/// `package:dart_style`-backed formatter. The save pipeline only consults
/// it when the per-document formatOnSave toggle is set; the default is
/// off, because diff-minimality is the editor's product invariant.
final formatServiceProvider = Provider<FormatService>((ref) => FormatService());

/// Per-document undo/redo history. Notifier holds the per-URI stacks;
/// the [WorkspaceController] is the only writer.
final editHistoryProvider =
    NotifierProvider<EditHistoryService, Map<String, DocumentHistory>>(
  EditHistoryService.new,
);

/// Stateless session loader/saver. The controller persists open-tab
/// state to `<projectRoot>/.dart_tool/loom/session.json` whenever tab
/// state changes, and restores it after `openProject`.
final sessionPersistenceServiceProvider = Provider<SessionPersistenceService>(
  (ref) => const SessionPersistenceService(),
);

/// Per-document opt-in for `dart_style` on save. Default off. The toggle
/// lives on the property inspector header so users can flip it
/// per-document without leaving the editing surface.
class FormatOnSaveNotifier extends Notifier<Map<String, bool>> {
  @override
  Map<String, bool> build() => const <String, bool>{};

  bool get(String uri) => state[uri] ?? false;

  void set(String uri, bool value) {
    if (get(uri) == value) return;
    state = <String, bool>{...state, uri: value};
  }
}

final formatOnSaveProvider =
    NotifierProvider<FormatOnSaveNotifier, Map<String, bool>>(
  FormatOnSaveNotifier.new,
);

// `canUndoActiveProvider` / `canRedoActiveProvider` live in
// document_providers.dart because they read `activeDocumentUriProvider`.
