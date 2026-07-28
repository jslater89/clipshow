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
        version: 14,
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
              annotations TEXT,
              file_size_bytes INTEGER NOT NULL,
              modified_at_ms INTEGER NOT NULL,
              created_at_ms INTEGER NOT NULL,
              duration_ms INTEGER,
              media_issue TEXT NOT NULL DEFAULT 'none',
              media_issue_detail TEXT
            );
          """);
          await db.execute("""
            CREATE INDEX idx_master_media_files_modified_at_ms
            ON master_media_files(modified_at_ms DESC);
          """);
          await _createClipAndTagTables(db);
          await _createTagSetsTable(db);
          await _createWorkspaceSettingsTables(db);
          // Defaults aligned with CapturePathsSettings / PlayoutRecordPathsSettings.
          // Operators may remove these; open/save does not force them back.
          await db.rawInsert(
            "INSERT OR IGNORE INTO ignored_folders (relative_path) VALUES (?)",
            <Object?>["recordings"],
          );
          await db.rawInsert(
            "INSERT OR IGNORE INTO ignored_folders (relative_path) VALUES (?)",
            <Object?>["export"],
          );
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
          if (oldVersion < 6) {
            await _addMasterDurationMsColumnIfMissing(db);
          }
          if (oldVersion < 7) {
            await _addObsCaptureSceneColumnIfMissing(db);
            await db.rawInsert(
              "INSERT OR IGNORE INTO ignored_folders (relative_path) VALUES (?)",
              <Object?>["recordings"],
            );
          }
          if (oldVersion < 8) {
            await _upgradeToV8TagSemantics(db);
          }
          if (oldVersion < 9) {
            await _upgradeToV9SavedTagSemanticColumn(db);
          }
          if (oldVersion < 10) {
            await _addAnnotationsColumnsIfMissing(db);
          }
          if (oldVersion < 11) {
            await _upgradeToV11TagSets(db);
          }
          if (oldVersion < 12) {
            await _upgradeToV12TagSetsIdempotent(db);
          }
          if (oldVersion < 13) {
            await _addObsOsgSourceColumnIfMissing(db);
          }
          if (oldVersion < 14) {
            // One-time seed for workspaces created before playout output default.
            await db.rawInsert(
              "INSERT OR IGNORE INTO ignored_folders (relative_path) VALUES (?)",
              <Object?>["export"],
            );
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
        annotations TEXT,
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
      CREATE TABLE tag_semantic_types (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE COLLATE NOCASE,
        icon_code_point INTEGER
      );
    """);
    await db.execute("""
      CREATE TABLE media_tags (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        media_type TEXT NOT NULL CHECK(media_type IN ('master', 'clip', 'tag_set')),
        media_id INTEGER NOT NULL,
        tag_id INTEGER NOT NULL,
        semantic_type_id INTEGER,
        FOREIGN KEY(tag_id) REFERENCES tags(id) ON DELETE CASCADE,
        FOREIGN KEY(semantic_type_id) REFERENCES tag_semantic_types(id) ON DELETE SET NULL,
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
        name TEXT NOT NULL UNIQUE COLLATE NOCASE,
        semantic_type_id INTEGER REFERENCES tag_semantic_types(id) ON DELETE SET NULL
      );
    """);
  }

  Future<void> _createTagSetsTable(Database db) async {
    await db.execute("""
      CREATE TABLE IF NOT EXISTS tag_sets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE COLLATE NOCASE,
        annotations TEXT,
        created_at_ms INTEGER NOT NULL
      );
    """);
    await db.execute("""
      CREATE INDEX IF NOT EXISTS idx_tag_sets_created_at_ms
      ON tag_sets(created_at_ms DESC);
    """);
  }

  Future<void> _upgradeToV11TagSets(Database db) async {
    await _createTagSetsTable(db);
    await _addObsOsgSceneColumnIfMissing(db);
    await _rebuildMediaTagsForTagSetSupport(db);
  }

  /// Idempotent pass for workspaces that already had tag_sets from a parallel
  /// migration path before v12 (rebase / partial upgrade).
  Future<void> _upgradeToV12TagSetsIdempotent(Database db) async {
    await _createTagSetsTable(db);
    await _addObsOsgSceneColumnIfMissing(db);
    await _rebuildMediaTagsForTagSetSupport(db);
  }

  Future<void> _addObsOsgSceneColumnIfMissing(Database db) async {
    final List<Map<String, Object?>> tables = await db.rawQuery("""
      SELECT name FROM sqlite_master
      WHERE type = 'table' AND name = 'scene_switch_profiles'
      """);
    if (tables.isEmpty) {
      return;
    }
    final List<Map<String, Object?>> columns = await db.rawQuery(
      "PRAGMA table_info(scene_switch_profiles);",
    );
    final bool hasColumn = columns.any(
      (Map<String, Object?> row) => row["name"] == "obs_osg_scene",
    );
    if (!hasColumn) {
      await db.execute("""
        ALTER TABLE scene_switch_profiles
        ADD COLUMN obs_osg_scene TEXT;
      """);
    }
  }

  Future<void> _addObsOsgSourceColumnIfMissing(Database db) async {
    final List<Map<String, Object?>> tables = await db.rawQuery("""
      SELECT name FROM sqlite_master
      WHERE type = 'table' AND name = 'scene_switch_profiles'
      """);
    if (tables.isEmpty) {
      return;
    }
    final List<Map<String, Object?>> columns = await db.rawQuery(
      "PRAGMA table_info(scene_switch_profiles);",
    );
    final bool hasColumn = columns.any(
      (Map<String, Object?> row) => row["name"] == "obs_osg_source",
    );
    if (!hasColumn) {
      await db.execute("""
        ALTER TABLE scene_switch_profiles
        ADD COLUMN obs_osg_source TEXT;
      """);
    }
  }

  Future<bool> _mediaTagsSupportsTagSet(Database db) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'media_tags'",
    );
    if (rows.isEmpty) {
      return false;
    }
    final Object? sql = rows.first["sql"];
    return sql is String && sql.contains("'tag_set'");
  }

  Future<void> _rebuildMediaTagsForTagSetSupport(Database db) async {
    final List<Map<String, Object?>> tables = await db.rawQuery("""
      SELECT name FROM sqlite_master
      WHERE type = 'table' AND name = 'media_tags'
      """);
    if (tables.isEmpty) {
      return;
    }
    if (await _mediaTagsSupportsTagSet(db)) {
      return;
    }
    await db.execute("PRAGMA foreign_keys = OFF;");
    await db.transaction((Transaction txn) async {
      await txn.execute("""
        CREATE TABLE media_tags_new (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          media_type TEXT NOT NULL CHECK(media_type IN ('master', 'clip', 'tag_set')),
          media_id INTEGER NOT NULL,
          tag_id INTEGER NOT NULL,
          semantic_type_id INTEGER,
          FOREIGN KEY(tag_id) REFERENCES tags(id) ON DELETE CASCADE,
          FOREIGN KEY(semantic_type_id) REFERENCES tag_semantic_types(id) ON DELETE SET NULL,
          UNIQUE(media_type, media_id, tag_id)
        );
      """);
      await txn.execute("""
        INSERT INTO media_tags_new (
          id, media_type, media_id, tag_id, semantic_type_id
        )
        SELECT id, media_type, media_id, tag_id, semantic_type_id
        FROM media_tags;
      """);
      await txn.execute("DROP TABLE media_tags;");
      await txn.execute("ALTER TABLE media_tags_new RENAME TO media_tags;");
      await txn.execute("""
        CREATE INDEX IF NOT EXISTS idx_media_tags_media_ref
        ON media_tags(media_type, media_id);
      """);
    });
    await db.execute("PRAGMA foreign_keys = ON;");
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
        obs_capture_scene TEXT,
        obs_osg_scene TEXT,
        obs_osg_source TEXT,
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

  Future<void> _addObsCaptureSceneColumnIfMissing(Database db) async {
    final List<Map<String, Object?>> columns = await db.rawQuery(
      "PRAGMA table_info(scene_switch_profiles);",
    );
    final bool hasColumn = columns.any(
      (Map<String, Object?> row) => row["name"] == "obs_capture_scene",
    );
    if (!hasColumn) {
      await db.execute("""
        ALTER TABLE scene_switch_profiles
        ADD COLUMN obs_capture_scene TEXT;
      """);
    }
  }

  Future<void> _addAnnotationsColumnsIfMissing(Database db) async {
    final List<Map<String, Object?>> existingTables = await db.rawQuery("""
      SELECT name FROM sqlite_master
      WHERE type = 'table' AND name IN ('master_media_files', 'clips')
      """);
    final Set<String> names = existingTables
        .map((Map<String, Object?> r) => r["name"] as String?)
        .whereType<String>()
        .toSet();

    if (names.contains("master_media_files")) {
      final List<Map<String, Object?>> masterColumns = await db.rawQuery(
        "PRAGMA table_info(master_media_files);",
      );
      final bool masterHas = masterColumns.any(
        (Map<String, Object?> row) => row["name"] == "annotations",
      );
      if (!masterHas) {
        await db.execute("""
          ALTER TABLE master_media_files
          ADD COLUMN annotations TEXT;
        """);
      }
    }

    if (names.contains("clips")) {
      final List<Map<String, Object?>> clipColumns = await db.rawQuery(
        "PRAGMA table_info(clips);",
      );
      final bool clipHas = clipColumns.any(
        (Map<String, Object?> row) => row["name"] == "annotations",
      );
      if (!clipHas) {
        await db.execute("""
          ALTER TABLE clips
          ADD COLUMN annotations TEXT;
        """);
      }
    }
  }

  Future<void> _upgradeToV8TagSemantics(Database db) async {
    await db.execute("""
      CREATE TABLE IF NOT EXISTS tag_semantic_types (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE COLLATE NOCASE,
        icon_code_point INTEGER
      );
    """);
    final List<Map<String, Object?>> mtCols = await db.rawQuery(
      "PRAGMA table_info(media_tags);",
    );
    final bool hasSemantic = mtCols.any(
      (Map<String, Object?> row) => row["name"] == "semantic_type_id",
    );
    if (!hasSemantic) {
      await db.execute("""
        ALTER TABLE media_tags
        ADD COLUMN semantic_type_id INTEGER
        REFERENCES tag_semantic_types(id) ON DELETE SET NULL;
      """);
    }
  }

  Future<void> _upgradeToV9SavedTagSemanticColumn(Database db) async {
    final List<Map<String, Object?>> cols = await db.rawQuery(
      "PRAGMA table_info(saved_tags);",
    );
    final bool hasSemantic = cols.any(
      (Map<String, Object?> row) => row["name"] == "semantic_type_id",
    );
    if (!hasSemantic) {
      await db.execute("""
        ALTER TABLE saved_tags
        ADD COLUMN semantic_type_id INTEGER
        REFERENCES tag_semantic_types(id) ON DELETE SET NULL;
      """);
    }
  }

  Future<void> _addMasterDurationMsColumnIfMissing(Database db) async {
    final List<Map<String, Object?>> masterColumns = await db.rawQuery(
      "PRAGMA table_info(master_media_files);",
    );
    final bool masterHasColumn = masterColumns.any(
      (Map<String, Object?> row) => row["name"] == "duration_ms",
    );
    if (!masterHasColumn) {
      await db.execute("""
        ALTER TABLE master_media_files
        ADD COLUMN duration_ms INTEGER;
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
