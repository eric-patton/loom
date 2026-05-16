import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/open_document.dart';

/// Owns the `{uri → OpenDocument}` map for the editor's open-tab set.
/// Held by `openDocumentsProvider`; mutated through these methods so
/// every tab edit produces a new map reference and triggers consumer
/// rebuilds.
class OpenDocumentsNotifier extends Notifier<Map<String, OpenDocument>> {
  @override
  Map<String, OpenDocument> build() => const <String, OpenDocument>{};

  /// Adds (or replaces) the entry for [doc.uri].
  void open(OpenDocument doc) {
    state = <String, OpenDocument>{...state, doc.uri: doc};
  }

  /// Removes the entry for [uri]. No-op if the URI is not open.
  void close(String uri) {
    if (!state.containsKey(uri)) return;
    final next = <String, OpenDocument>{...state}..remove(uri);
    state = next;
  }

  /// Replaces every tab's state. Used when the user opens a new project
  /// (the previous project's tabs are discarded).
  void reset() {
    state = const <String, OpenDocument>{};
  }

  /// Updates the working-buffer source for [uri].
  void updateWorking(String uri, String newSource) {
    final current = state[uri];
    if (current == null) return;
    state = <String, OpenDocument>{
      ...state,
      uri: current.copyWith(workingSource: newSource),
    };
  }

  /// After a successful atomic write, set both `diskSource` and
  /// `workingSource` to [savedSource] so `isDirty` flips back to false.
  void markSaved(String uri, String savedSource) {
    final current = state[uri];
    if (current == null) return;
    state = <String, OpenDocument>{
      ...state,
      uri: current.copyWith(
        diskSource: savedSource,
        workingSource: savedSource,
      ),
    };
  }
}
