class MasterMediaFile {
  const MasterMediaFile({
    required this.id,
    required this.filePath,
    required this.fileName,
    required this.fileSizeBytes,
    required this.modifiedAtMs,
    required this.createdAtMs,
  });

  final int id;
  final String filePath;
  final String fileName;
  final int fileSizeBytes;
  final int modifiedAtMs;
  final int createdAtMs;

  factory MasterMediaFile.fromMap(Map<String, Object?> map) {
    return MasterMediaFile(
      id: map["id"]! as int,
      filePath: map["file_path"]! as String,
      fileName: map["file_name"]! as String,
      fileSizeBytes: map["file_size_bytes"]! as int,
      modifiedAtMs: map["modified_at_ms"]! as int,
      createdAtMs: map["created_at_ms"]! as int,
    );
  }
}
