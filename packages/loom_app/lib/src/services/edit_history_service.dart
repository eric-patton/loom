/// Per-document undo/redo history.
///
/// M12 replaces the M11 stub: every committed property edit pushes an
/// entry onto the active document's undo stack; `undo()` returns the
/// pre-edit source, `redo()` returns the post-edit source, and a fresh
/// record clears the redo stack.
///
/// Held by [editHistoryProvider] as a Riverpod [Notifier] so the UI
/// can watch `canUndo` / `canRedo` per-document without manual change
/// notifications.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One step on the per-document undo stack. Snapshot-based by design —
/// kernel verbs are not yet reversible operations, and full-source
/// snapshots cost little against typical Dart file sizes while keeping
/// the implementation independent of any kernel edit type.
class HistoryEntry {
  const HistoryEntry({
    required this.label,
    required this.beforeSource,
    required this.afterSource,
  });

  /// Human-readable label, surfaced in tooltips and tests.
  final String label;

  /// Source on disk before the edit was applied.
  final String beforeSource;

  /// Source on disk after the edit was applied (and after formatting,
  /// if formatOnSave was enabled at the time of the edit).
  final String afterSource;
}

/// Per-document history: an undo stack of entries that have been
/// applied, and a redo stack of entries that were undone and can be
/// re-applied. Recording a fresh edit clears the redo stack.
class DocumentHistory {
  const DocumentHistory({
    this.undoStack = const <HistoryEntry>[],
    this.redoStack = const <HistoryEntry>[],
  });

  final List<HistoryEntry> undoStack;
  final List<HistoryEntry> redoStack;

  bool get canUndo => undoStack.isNotEmpty;
  bool get canRedo => redoStack.isNotEmpty;
}

/// Notifier holding `{uri → DocumentHistory}`. All mutations go through
/// the methods on this class; consumers read state via the provider.
class EditHistoryService extends Notifier<Map<String, DocumentHistory>> {
  @override
  Map<String, DocumentHistory> build() => const <String, DocumentHistory>{};

  /// Records a new edit on [uri]'s undo stack and clears its redo
  /// stack. Called after a successful disk write — entries point at
  /// the bytes that actually landed on disk.
  void record({
    required String uri,
    required String label,
    required String beforeSource,
    required String afterSource,
  }) {
    if (beforeSource == afterSource) return;
    final existing = state[uri] ?? const DocumentHistory();
    final updated = DocumentHistory(
      undoStack: <HistoryEntry>[
        ...existing.undoStack,
        HistoryEntry(
          label: label,
          beforeSource: beforeSource,
          afterSource: afterSource,
        ),
      ],
    );
    state = <String, DocumentHistory>{...state, uri: updated};
  }

  /// Pops the most recent entry off [uri]'s undo stack and pushes it
  /// onto the redo stack. Returns the entry so the caller can restore
  /// its `beforeSource`. Returns null when nothing is on the undo stack.
  HistoryEntry? popUndo(String uri) {
    final existing = state[uri];
    if (existing == null || existing.undoStack.isEmpty) return null;
    final top = existing.undoStack.last;
    final updated = DocumentHistory(
      undoStack: existing.undoStack.sublist(0, existing.undoStack.length - 1),
      redoStack: <HistoryEntry>[...existing.redoStack, top],
    );
    state = <String, DocumentHistory>{...state, uri: updated};
    return top;
  }

  /// Pops the most recent entry off [uri]'s redo stack and pushes it
  /// onto the undo stack. Returns the entry so the caller can restore
  /// its `afterSource`. Returns null when nothing is on the redo stack.
  HistoryEntry? popRedo(String uri) {
    final existing = state[uri];
    if (existing == null || existing.redoStack.isEmpty) return null;
    final top = existing.redoStack.last;
    final updated = DocumentHistory(
      undoStack: <HistoryEntry>[...existing.undoStack, top],
      redoStack: existing.redoStack.sublist(0, existing.redoStack.length - 1),
    );
    state = <String, DocumentHistory>{...state, uri: updated};
    return top;
  }

  /// Drops every entry for [uri]. Called when a document closes or
  /// when a project is reopened.
  void clear(String uri) {
    if (!state.containsKey(uri)) return;
    final next = <String, DocumentHistory>{...state}..remove(uri);
    state = next;
  }

  /// Clears every document's history. Called on project open.
  void clearAll() {
    state = const <String, DocumentHistory>{};
  }

  bool canUndo(String uri) => state[uri]?.canUndo ?? false;
  bool canRedo(String uri) => state[uri]?.canRedo ?? false;
}
