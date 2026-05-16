import 'package:path/path.dart' as p;

/// One tab in the editor — a Dart source file the user has open. Tracks
/// both the last-known on-disk content and the in-editor working content
/// so the inspector can show a dirty indicator and the save pipeline can
/// detect external changes. In M11 the working state matches disk after
/// every commit (we save synchronously on Enter / focus-loss); M12+ will
/// keep a longer-lived working buffer behind explicit save.
class OpenDocument {
  const OpenDocument({
    required this.uri,
    required this.pathOnDisk,
    required this.diskSource,
    required this.workingSource,
  });

  /// Canonical document identifier. By convention this is
  /// `Uri.file(pathOnDisk).toString()` so it matches what the kernel
  /// uses to key `ProjectModel.fromSources`.
  final String uri;

  /// Native filesystem path used for I/O.
  final String pathOnDisk;

  /// Last-known content on disk. Updated after a successful atomic
  /// save via [OpenDocument.copyWith].
  final String diskSource;

  /// Content the editor believes the file should contain. Differs from
  /// [diskSource] only while a commit is in flight in M11.
  final String workingSource;

  /// True if the working buffer has drifted from disk content.
  bool get isDirty => diskSource != workingSource;

  /// Short display name used by the tab strip — the file's basename.
  String get displayName => p.basename(pathOnDisk);

  OpenDocument copyWith({String? diskSource, String? workingSource}) =>
      OpenDocument(
        uri: uri,
        pathOnDisk: pathOnDisk,
        diskSource: diskSource ?? this.diskSource,
        workingSource: workingSource ?? this.workingSource,
      );
}
