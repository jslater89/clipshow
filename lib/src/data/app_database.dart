import "package:sqflite_common_ffi/sqflite_ffi.dart";

import 'package:obs_clipshow/src/media/workspace.dart';

class AppDatabase {
  AppDatabase();

  static bool _isInitialized = false;

  Future<Database> openForWorkspace(Workspace workspace) async {
    _initializeDriverOnce();
    return databaseFactoryFfi.openDatabase(
      workspace.databasePath,
      options: OpenDatabaseOptions(
        version: 5,
        onConfigure: (Database db) async {
          await db.execute("PRAGMA foreign_keys = ON;");
        },
        onCreate: (Database db, int version) async {
          await db.execute("""
            CREATE TABLE master_media_files (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              file_path TEXT NOT NULL UNIQUE,
              file_name TEXT NOT NULL,
              display_name_override TEXT,
              file_size_bytes INTEGER NOT NULL,
              modified_at_ms INTEGER NOT NULL,
              created_at_ms INTEGER NOT NULL,
              media_issue TEXT NOT NULL DEFAULT 'none',
              media_issue_detail TEXT
            );
          """);
          await db.execute("""
            CREATE INDEX idx_master_media_files_modified_at_ms
            ON master_media_files(modified_at_ms DESC);
          """);
          await _createClipAndTagTables(db);
          await _createWorkspaceSettingsTables(db);
        },
        onUpgrade: (Database db, int oldVersion, int newVersion) async {
          if (oldVersion < 2) {
            await db.execute("""
              ALTER TABLE master_media_files
              ADD COLUMN media_issue TEXT NOT NULL DEFAULT 'none';
            """);
            await db.execute("""
              ALTER TABLE master_media_files
              ADD COLUMN media_issue_detail TEXT;
            """);
          }
          if (oldVersion < 3) {
            await _createClipAndTagTables(db);
          }
          if (oldVersion < 4) {
            await _createWorkspaceSettingsTables(db);
          }
          if (oldVersion < 5) {
            await _addDisplayNameOverrideColumnsIfMissing(db);
          }
        },
      ),
    );
  }

  Future<void> _createClipAndTagTables(Database db) async {
    await db.execute("""
      CREATE TABLE clips (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        master_media_id INTEGER NOT NULL,
        display_name_override TEXT,
        in_ms INTEGER NOT NULL,
        out_ms INTEGER,
        created_at_ms INTEGER NOT NULL,
        FOREIGN KEY(master_media_id) REFERENCES master_media_files(id) ON DELETE CASCADE
      );
    """);
    await db.execute("""
      CREATE INDEX idx_clips_master_media_id
      ON clips(master_media_id);
    """);
    await db.execute("""
      CREATE TABLE tags (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE COLLATE NOCASE
      );
    """);
    await db.execute("""
      CREATE TABLE media_tags (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        media_type TEXT NOT NULL CHECK(media_type IN ('master', 'clip')),
        media_id INTEGER NOT NULL,
        tag_id INTEGER NOT NULL,
        FOREIGN KEY(tag_id) REFERENCES tags(id) ON DELETE CASCADE,
        UNIQUE(media_type, media_id, tag_id)
      );
    """);
    await db.execute("""
      CREATE INDEX idx_media_tags_media_ref
      ON media_tags(media_type, media_id);
    """);
    await db.execute("""
      CREATE TABLE saved_tags (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE COLLATE NOCASE
      );
    """);
  }

  Future<void> _createWorkspaceSettingsTables(Database db) async {
    await db.execute("""
      CREATE TABLE workspace_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      );
    """);
    await db.execute("""
      CREATE TABLE scene_switch_profiles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        profile_type TEXT NOT NULL CHECK(profile_type IN ('obs', 'webhook')),
        name TEXT NOT NULL,
        enabled INTEGER NOT NULL DEFAULT 1,
        obs_server_address TEXT,
        obs_port INTEGER,
        obs_password TEXT,
        obs_video_scene TEXT,
        obs_face_scene TEXT,
        webhook_url TEXT,
        webhook_method TEXT CHECK(webhook_method IN ('GET', 'POST')),
        webhook_get_query_param TEXT,
        webhook_post_body_type TEXT CHECK(webhook_post_body_type IN ('form', 'json')),
        webhook_scene_key TEXT
      );
    """);
    await db.execute("""
      CREATE INDEX idx_scene_switch_profiles_type
      ON scene_switch_profiles(profile_type);
    """);
    await db.execute("""
      CREATE TABLE ignored_folders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        relative_path TEXT NOT NULL UNIQUE
      );
    """);
  }

  Future<void> _addDisplayNameOverrideColumnsIfMissing(Database db) async {
    final List<Map<String, Object?>> masterColumns = await db.rawQuery(
      "PRAGMA table_info(master_media_files);",
    );
    final bool masterHasColumn = masterColumns.any(
      (Map<String, Object?> row) => row["name"] == "display_name_override",
    );
    if (!masterHasColumn) {
      await db.execute("""
        ALTER TABLE master_media_files
        ADD COLUMN display_name_override TEXT;
      """);
    }

    final List<Map<String, Object?>> clipColumns = await db.rawQuery(
      "PRAGMA table_info(clips);",
    );
    final bool clipsHasColumn = clipColumns.any(
      (Map<String, Object?> row) => row["name"] == "display_name_override",
    );
    if (!clipsHasColumn) {
      await db.execute("""
        ALTER TABLE clips
        ADD COLUMN display_name_override TEXT;
      """);
    }
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
