/// Persisted issue state for a row in [master_media_files] (and in-memory model).
enum MediaIssue {
  none,
  empty,
  unreadable,
}

class MasterMediaFile {
  const MasterMediaFile({
    required this.id,
    required this.filePath,
    required this.fileName,
    this.displayNameOverride,
    required this.fileSizeBytes,
    required this.modifiedAtMs,
    required this.createdAtMs,
    this.durationMs,
    this.mediaIssue = MediaIssue.none,
    this.mediaIssueDetail,
  });

  final int id;
  final String filePath;
  final String fileName;
  final String? displayNameOverride;
  final int fileSizeBytes;
  final int modifiedAtMs;
  final int createdAtMs;
  final int? durationMs;
  final MediaIssue mediaIssue;
  final String? mediaIssueDetail;

  factory MasterMediaFile.fromMap(Map<String, Object?> map) {
    return MasterMediaFile(
      id: map["id"]! as int,
      filePath: map["file_path"]! as String,
      fileName: map["file_name"]! as String,
      displayNameOverride: map["display_name_override"] as String?,
      fileSizeBytes: map["file_size_bytes"]! as int,
      modifiedAtMs: map["modified_at_ms"]! as int,
      createdAtMs: map["created_at_ms"]! as int,
      durationMs: map["duration_ms"] as int?,
      mediaIssue: _parseMediaIssue(map["media_issue"] as String?),
      mediaIssueDetail: map["media_issue_detail"] as String?,
    );
  }

  static MediaIssue _parseMediaIssue(String? raw) {
    if (raw == null || raw.isEmpty) {
      return MediaIssue.none;
    }
    return MediaIssue.values.firstWhere(
      (MediaIssue e) => e.name == raw,
      orElse: () => MediaIssue.none,
    );
  }
}
