import "package:sqflite/sqflite.dart";

import "../media/master_media_file.dart";

class MediaRepository {
  MediaRepository(this._database);

  final Database _database;

  Future<void> upsertMasterMedia({
    required String filePath,
    required String fileName,
    required int fileSizeBytes,
    required int modifiedAtMs,
    required int createdAtMs,
  }) async {
    await _database.insert(
      "master_media_files",
      <String, Object?>{
        "file_path": filePath,
        "file_name": fileName,
        "file_size_bytes": fileSizeBytes,
        "modified_at_ms": modifiedAtMs,
        "created_at_ms": createdAtMs,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteByPath(String filePath) async {
    await _database.delete(
      "master_media_files",
      where: "file_path = ?",
      whereArgs: <Object?>[filePath],
    );
  }

  Future<List<MasterMediaFile>> listAll() async {
    final List<Map<String, Object?>> rows = await _database.query(
      "master_media_files",
      orderBy: "modified_at_ms DESC, file_name ASC",
    );
    return rows.map(MasterMediaFile.fromMap).toList();
  }
}
