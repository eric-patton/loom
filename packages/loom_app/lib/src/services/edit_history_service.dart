/// Per-document undo/redo history. M11 stub: edits are not recorded and
/// `canUndo` / `canRedo` always return false. M12 implements the real
/// stack (per-document `{label, beforeSource, afterSource}` triples,
/// Ctrl+Z / Ctrl+Y bindings).
///
/// The stub still lets the rest of the system call these methods so
/// M12 only needs to flip the implementation, not rewire callers.
class EditHistoryService {
  const EditHistoryService();

  void recordEdit({
    required String uri,
    required String label,
    required String beforeSource,
    required String afterSource,
  }) {
    // M11 stub.
  }

  bool canUndo(String uri) => false;
  bool canRedo(String uri) => false;

  /// Returns the new source after applying the undo, or null if no undo
  /// is available. M11 always returns null.
  String? undo(String uri) => null;

  /// Returns the new source after applying the redo, or null if no redo
  /// is available. M11 always returns null.
  String? redo(String uri) => null;
}
