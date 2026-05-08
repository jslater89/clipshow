class MediaClip {
  const MediaClip({
    required this.id,
    required this.masterMediaId,
    required this.filePath,
    required this.fileName,
    this.displayNameOverride,
    required this.inMs,
    required this.outMs,
    required this.createdAtMs,
  });

  final int id;
  final int masterMediaId;
  final String filePath;
  final String fileName;
  final String? displayNameOverride;
  final int inMs;
  final int? outMs;
  final int createdAtMs;

  factory MediaClip.fromMap(Map<String, Object?> map) {
    return MediaClip(
      id: map["id"]! as int,
      masterMediaId: map["master_media_id"]! as int,
      filePath: map["file_path"]! as String,
      fileName: map["file_name"]! as String,
      displayNameOverride: map["display_name_override"] as String?,
      inMs: map["in_ms"]! as int,
      outMs: map["out_ms"] as int?,
      createdAtMs: map["created_at_ms"]! as int,
    );
  }
}
