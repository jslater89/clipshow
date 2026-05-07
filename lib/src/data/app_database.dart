import "package:sqflite_common_ffi/sqflite_ffi.dart";

import "../media/workspace.dart";

class AppDatabase {
  AppDatabase();

  static bool _isInitialized = false;

  Future<Database> openForWorkspace(Workspace workspace) async {
    _initializeDriverOnce();
    return databaseFactoryFfi.openDatabase(
      workspace.databasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (Database db, int version) async {
          await db.execute("""
            CREATE TABLE master_media_files (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              file_path TEXT NOT NULL UNIQUE,
              file_name TEXT NOT NULL,
              file_size_bytes INTEGER NOT NULL,
              modified_at_ms INTEGER NOT NULL,
              created_at_ms INTEGER NOT NULL
            );
          """);
          await db.execute("""
            CREATE INDEX idx_master_media_files_modified_at_ms
            ON master_media_files(modified_at_ms DESC);
          """);
        },
      ),
    );
  }

  void _initializeDriverOnce() {
    if (_isInitialized) {
      return;
    }
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    _isInitialized = true;
  }
}
