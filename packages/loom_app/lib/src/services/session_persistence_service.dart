/// Persists per-project editor session (open tabs + active tab) under
/// `<projectRoot>/.dart_tool/loom/session.json` so the next time the
/// user opens the same project the editor reopens what they were
/// working on. `.dart_tool/` is already ignored by Flutter, so the file
/// never enters version control.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// One persisted editor session.
class SavedSession {
  const SavedSession({
    required this.openRelativePaths,
    required this.activeRelativePath,
  });

  /// Paths relative to project root, in tab order.
  final List<String> openRelativePaths;

  /// The active tab's relative path, or null when none was active when
  /// the session was saved.
  final String? activeRelativePath;

  static const SavedSession empty = SavedSession(
    openRelativePaths: <String>[],
    activeRelativePath: null,
  );

  Map<String, Object?> toJson() => <String, Object?>{
        'version': 1,
        'open': openRelativePaths,
        'active': activeRelativePath,
      };

  static SavedSession? fromJson(Object? raw) {
    if (raw is! Map<String, Object?>) return null;
    final open = raw['open'];
    if (open is! List) return null;
    final paths = <String>[
      for (final entry in open)
        if (entry is String) entry,
    ];
    final active = raw['active'];
    final activeStr = active is String ? active : null;
    return SavedSession(
      openRelativePaths: paths,
      activeRelativePath: activeStr,
    );
  }
}

/// Reads + writes the per-project session JSON. Stateless; failures are
/// silent — a corrupted session file should not block opening the
/// project.
class SessionPersistenceService {
  const SessionPersistenceService();

  static const String _relativeFilePath = '.dart_tool/loom/session.json';

  String _sessionPath(String projectRoot) =>
      p.join(projectRoot, _relativeFilePath);

  /// Attempts to load the session for [projectRoot]. Returns null when
  /// no file is present, the file is malformed, or any I/O error
  /// occurs.
  Future<SavedSession?> tryLoad(String projectRoot) async {
    try {
      final file = File(_sessionPath(projectRoot));
      if (!file.existsSync()) return null;
      final raw = jsonDecode(await file.readAsString());
      return SavedSession.fromJson(raw);
    } on Object {
      return null;
    }
  }

  /// Writes [session] to disk, creating the `.dart_tool/loom/`
  /// directory if needed. Silent on failure — losing a session save
  /// should not surface as an error to the user.
  Future<void> save(String projectRoot, SavedSession session) async {
    try {
      final file = File(_sessionPath(projectRoot));
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(session.toJson()), flush: true);
    } on Object {
      // Best-effort: a stale session is acceptable.
    }
  }

  /// Converts a kernel `file://` URI to a project-relative POSIX-style
  /// path. Returns null when [uri] is not under [projectRoot].
  String? uriToRelative(String uri, String projectRoot) {
    try {
      final filePath = Uri.parse(uri).toFilePath();
      final rel = p.relative(filePath, from: projectRoot);
      if (rel.startsWith('..')) return null;
      return p.posix.joinAll(p.split(rel));
    } on Object {
      return null;
    }
  }

  /// Converts a project-relative path back to a canonical `file://`
  /// URI under [projectRoot].
  String relativeToUri(String relative, String projectRoot) {
    final absolute = p.canonicalize(p.join(projectRoot, relative));
    return Uri.file(absolute).toString();
  }
}
