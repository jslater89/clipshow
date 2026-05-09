import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:path/path.dart" as p;
import "package:sqflite_common_ffi/sqflite_ffi.dart";

import "package:obs_clipshow/src/data/app_database.dart";
import "package:obs_clipshow/src/data/media_repository.dart";
import "package:obs_clipshow/src/media/master_media_file.dart";
import "package:obs_clipshow/src/media/media_clip.dart";
import "package:obs_clipshow/src/media/media_list_item.dart";
import "package:obs_clipshow/src/media/workspace.dart";
import "package:obs_clipshow/src/workspace/workspace_settings.dart";

void main() {
  group("MediaRepository", () {
    late Directory tempDirectory;

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp(
        "obs_clipshow_test_",
      );
    });

    tearDown(() async {
      await tempDirectory.delete(recursive: true);
    });

    test("creates database and performs CRUD operations", () async {
      final AppDatabase appDatabase = AppDatabase();
      final Workspace workspace = Workspace(rootPath: tempDirectory.path);
      final database = await appDatabase.openForWorkspace(workspace);
      final MediaRepository repository = MediaRepository(database);

      const String filePath = "highlight.mp4";
      await repository.upsertMasterMedia(
        filePath: filePath,
        fileName: "highlight.mp4",
        fileSizeBytes: 1024,
        modifiedAtMs: 2000,
        createdAtMs: 1000,
      );
      await repository.upsertMasterMedia(
        filePath: filePath,
        fileName: "highlight.mp4",
        fileSizeBytes: 2048,
        modifiedAtMs: 3000,
        createdAtMs: 1000,
      );

      final itemsAfterUpsert = await repository.listAll();
      expect(itemsAfterUpsert, hasLength(1));
      expect(itemsAfterUpsert.first.fileSizeBytes, 2048);
      expect(itemsAfterUpsert.first.filePath, filePath);

      await repository.deleteByPath(filePath);
      final itemsAfterDelete = await repository.listAll();
      expect(itemsAfterDelete, isEmpty);

      await database.close();
      expect(
        File(p.join(tempDirectory.path, "obs_clipshow.db")).existsSync(),
        isTrue,
      );
    });

    test("migrates legacy absolute master paths to workspace-relative rows", () async {
      final AppDatabase appDatabase = AppDatabase();
      final Workspace workspace = Workspace(rootPath: tempDirectory.path);
      final database = await appDatabase.openForWorkspace(workspace);
      final MediaRepository repository = MediaRepository(database);

      await repository.upsertMasterMedia(
        filePath: "drone/a.mp4",
        fileName: "a.mp4",
        fileSizeBytes: 100,
        modifiedAtMs: 100,
        createdAtMs: 100,
      );
      final MasterMediaFile inserted = (await repository.listAll()).single;
      await database.update(
        "master_media_files",
        <String, Object?>{
          "file_path": p.join(tempDirectory.path, "drone", "a.mp4"),
        },
        where: "id = ?",
        whereArgs: <Object?>[inserted.id],
      );

      await repository.migrateMasterPathsToWorkspaceRelative(
        tempDirectory.path,
      );
      final MasterMediaFile migrated = (await repository.listAll()).single;
      expect(migrated.filePath, "drone/a.mp4");

      await database.close();
    });

    test("second upsert keeps stored media issue fields", () async {
      final AppDatabase appDatabase = AppDatabase();
      final Workspace workspace = Workspace(rootPath: tempDirectory.path);
      final database = await appDatabase.openForWorkspace(workspace);
      final MediaRepository repository = MediaRepository(database);

      const String filePath = "fragile.mp4";
      await repository.upsertMasterMedia(
        filePath: filePath,
        fileName: "fragile.mp4",
        fileSizeBytes: 1024,
        modifiedAtMs: 2000,
        createdAtMs: 1000,
      );
      await repository.setMediaIssue(
        filePath,
        MediaIssue.unreadable,
        detail: "moov atom not found",
      );
      await repository.upsertMasterMedia(
        filePath: filePath,
        fileName: "fragile.mp4",
        fileSizeBytes: 2048,
        modifiedAtMs: 3000,
        createdAtMs: 1000,
      );

      final List<MasterMediaFile> items = await repository.listAll();
      expect(items, hasLength(1));
      expect(items.single.mediaIssue, MediaIssue.unreadable);
      expect(items.single.mediaIssueDetail, contains("moov"));

      await database.close();
    });

    test("persists clip rows and default master/clip tags", () async {
      final AppDatabase appDatabase = AppDatabase();
      final Workspace workspace = Workspace(rootPath: tempDirectory.path);
      final database = await appDatabase.openForWorkspace(workspace);
      final MediaRepository repository = MediaRepository(database);

      const String filePath = "source.mp4";
      await repository.upsertMasterMedia(
        filePath: filePath,
        fileName: "source.mp4",
        fileSizeBytes: 3000,
        modifiedAtMs: 3000,
        createdAtMs: 1000,
      );
      final MasterMediaFile master = (await repository.listAll()).single;
      await repository.addTagToMedia(
        mediaType: MediaListItemType.master,
        mediaId: master.id,
        tag: "Day 3",
      );
      final Set<String> masterTags = await repository.listTagsForMedia(
        mediaType: MediaListItemType.master,
        mediaId: master.id,
      );
      expect(masterTags.contains(MediaRepository.masterTag), isTrue);

      final int clipId = await repository.createClip(
        masterMediaId: master.id,
        inMs: 1000,
        outMs: 4000,
      );
      expect(clipId, greaterThan(0));
      final clips = await repository.listClips();
      expect(clips, hasLength(1));
      expect(clips.single.inMs, 1000);
      expect(clips.single.outMs, 4000);
      final Set<String> clipTags = await repository.listTagsForMedia(
        mediaType: MediaListItemType.clip,
        mediaId: clipId,
      );
      expect(clipTags.contains(MediaRepository.clipTag), isTrue);
      expect(clipTags.contains("Day 3"), isTrue);
      expect(clipTags.contains(MediaRepository.masterTag), isFalse);

      await database.close();
    });

    test("persists duration_ms on master media upsert", () async {
      final AppDatabase appDatabase = AppDatabase();
      final Workspace workspace = Workspace(rootPath: tempDirectory.path);
      final database = await appDatabase.openForWorkspace(workspace);
      final MediaRepository repository = MediaRepository(database);

      const String filePath = "timed.mp4";
      await repository.upsertMasterMedia(
        filePath: filePath,
        fileName: "timed.mp4",
        fileSizeBytes: 5000,
        modifiedAtMs: 2000,
        createdAtMs: 1000,
        durationMs: 90420,
      );
      final MasterMediaFile first = (await repository.listAll()).single;
      expect(first.durationMs, 90420);

      await repository.upsertMasterMedia(
        filePath: filePath,
        fileName: "timed.mp4",
        fileSizeBytes: 6000,
        modifiedAtMs: 3000,
        createdAtMs: 1000,
        durationMs: 120500,
      );
      final MasterMediaFile updated = (await repository.listAll()).single;
      expect(updated.durationMs, 120500);
      expect(updated.fileSizeBytes, 6000);

      await database.close();
    });

    test("persists display name overrides for masters and clips", () async {
      final AppDatabase appDatabase = AppDatabase();
      final Workspace workspace = Workspace(rootPath: tempDirectory.path);
      final database = await appDatabase.openForWorkspace(workspace);
      final MediaRepository repository = MediaRepository(database);

      await repository.upsertMasterMedia(
        filePath: "source.mp4",
        fileName: "source.mp4",
        fileSizeBytes: 3000,
        modifiedAtMs: 3000,
        createdAtMs: 1000,
      );
      final MasterMediaFile master = (await repository.listAll()).single;
      await repository.createClip(
        masterMediaId: master.id,
        inMs: 1000,
        outMs: 4000,
      );
      final MediaClip clip = (await repository.listClips()).single;

      await repository.setDisplayNameOverride(
        mediaType: MediaListItemType.master,
        mediaId: master.id,
        displayNameOverride: "Warmup Angle",
      );
      await repository.setDisplayNameOverride(
        mediaType: MediaListItemType.clip,
        mediaId: clip.id,
        displayNameOverride: "Goal Replay",
      );

      final MasterMediaFile updatedMaster = (await repository.listAll()).single;
      final MediaClip updatedClip = (await repository.listClips()).single;
      expect(updatedMaster.displayNameOverride, "Warmup Angle");
      expect(updatedClip.displayNameOverride, "Goal Replay");

      await repository.setDisplayNameOverride(
        mediaType: MediaListItemType.clip,
        mediaId: clip.id,
        displayNameOverride: " ",
      );
      final MediaClip resetClip = (await repository.listClips()).single;
      expect(resetClip.displayNameOverride, isNull);

      await database.close();
    });

    test("upgrades v2 workspace database to include new tag tables", () async {
      sqfliteFfiInit();
      final String dbPath = p.join(tempDirectory.path, "obs_clipshow.db");
      final Database legacy = await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (Database db, int version) async {
            await db.execute("""
              CREATE TABLE master_media_files (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                file_path TEXT NOT NULL UNIQUE,
                file_name TEXT NOT NULL,
                file_size_bytes INTEGER NOT NULL,
                modified_at_ms INTEGER NOT NULL,
                created_at_ms INTEGER NOT NULL,
                media_issue TEXT NOT NULL DEFAULT 'none',
                media_issue_detail TEXT
              );
            """);
          },
        ),
      );
      await legacy.close();

      final AppDatabase appDatabase = AppDatabase();
      final Workspace workspace = Workspace(rootPath: tempDirectory.path);
      final Database upgraded = await appDatabase.openForWorkspace(workspace);
      final List<Map<String, Object?>> tables = await upgraded.rawQuery("""
        SELECT name FROM sqlite_master
        WHERE type = 'table' AND name IN ('clips', 'tags', 'media_tags', 'saved_tags')
        ORDER BY name ASC
        """);
      expect(
        tables.map((Map<String, Object?> row) => row["name"]),
        orderedEquals(<String>["clips", "media_tags", "saved_tags", "tags"]),
      );
      await upgraded.close();
    });

    test("upgrades v3 workspace database to include settings tables", () async {
      sqfliteFfiInit();
      final String dbPath = p.join(tempDirectory.path, "obs_clipshow.db");
      final Database legacy = await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 3,
          onCreate: (Database db, int version) async {
            await db.execute("""
              CREATE TABLE master_media_files (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                file_path TEXT NOT NULL UNIQUE,
                file_name TEXT NOT NULL,
                file_size_bytes INTEGER NOT NULL,
                modified_at_ms INTEGER NOT NULL,
                created_at_ms INTEGER NOT NULL,
                media_issue TEXT NOT NULL DEFAULT 'none',
                media_issue_detail TEXT
              );
            """);
            await db.execute("""
              CREATE TABLE clips (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                master_media_id INTEGER NOT NULL,
                in_ms INTEGER NOT NULL,
                out_ms INTEGER,
                created_at_ms INTEGER NOT NULL
              );
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
                media_type TEXT NOT NULL,
                media_id INTEGER NOT NULL,
                tag_id INTEGER NOT NULL,
                UNIQUE(media_type, media_id, tag_id)
              );
            """);
            await db.execute("""
              CREATE TABLE saved_tags (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL UNIQUE COLLATE NOCASE
              );
            """);
          },
        ),
      );
      await legacy.close();

      final AppDatabase appDatabase = AppDatabase();
      final Workspace workspace = Workspace(rootPath: tempDirectory.path);
      final Database upgraded = await appDatabase.openForWorkspace(workspace);
      final List<Map<String, Object?>> tables = await upgraded.rawQuery("""
        SELECT name FROM sqlite_master
        WHERE type = 'table'
          AND name IN ('workspace_settings', 'scene_switch_profiles', 'ignored_folders')
        ORDER BY name ASC
        """);
      expect(
        tables.map((Map<String, Object?> row) => row["name"]),
        orderedEquals(<String>[
          "ignored_folders",
          "scene_switch_profiles",
          "workspace_settings",
        ]),
      );
      await upgraded.close();
    });

    test(
      "upgrades v4 workspace database to include display name overrides",
      () async {
        sqfliteFfiInit();
        final String dbPath = p.join(tempDirectory.path, "obs_clipshow.db");
        final Database legacy = await databaseFactoryFfi.openDatabase(
          dbPath,
          options: OpenDatabaseOptions(
            version: 4,
            onCreate: (Database db, int version) async {
              await db.execute("""
              CREATE TABLE master_media_files (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                file_path TEXT NOT NULL UNIQUE,
                file_name TEXT NOT NULL,
                file_size_bytes INTEGER NOT NULL,
                modified_at_ms INTEGER NOT NULL,
                created_at_ms INTEGER NOT NULL,
                media_issue TEXT NOT NULL DEFAULT 'none',
                media_issue_detail TEXT
              );
            """);
              await db.execute("""
              CREATE TABLE clips (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                master_media_id INTEGER NOT NULL,
                in_ms INTEGER NOT NULL,
                out_ms INTEGER,
                created_at_ms INTEGER NOT NULL
              );
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
                media_type TEXT NOT NULL,
                media_id INTEGER NOT NULL,
                tag_id INTEGER NOT NULL,
                UNIQUE(media_type, media_id, tag_id)
              );
            """);
              await db.execute("""
              CREATE TABLE saved_tags (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL UNIQUE COLLATE NOCASE
              );
            """);
              await db.execute("""
              CREATE TABLE workspace_settings (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
              );
            """);
              await db.execute("""
              CREATE TABLE scene_switch_profiles (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                profile_type TEXT NOT NULL,
                name TEXT NOT NULL,
                enabled INTEGER NOT NULL DEFAULT 1
              );
            """);
              await db.execute("""
              CREATE TABLE ignored_folders (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                relative_path TEXT NOT NULL UNIQUE
              );
            """);
            },
          ),
        );
        await legacy.close();

        final AppDatabase appDatabase = AppDatabase();
        final Workspace workspace = Workspace(rootPath: tempDirectory.path);
        final Database upgraded = await appDatabase.openForWorkspace(workspace);
        final List<Map<String, Object?>> masterColumns = await upgraded
            .rawQuery("PRAGMA table_info(master_media_files);");
        final List<Map<String, Object?>> clipColumns = await upgraded.rawQuery(
          "PRAGMA table_info(clips);",
        );
        expect(
          masterColumns.any(
            (Map<String, Object?> row) =>
                row["name"] == "display_name_override",
          ),
          isTrue,
        );
        expect(
          clipColumns.any(
            (Map<String, Object?> row) =>
                row["name"] == "display_name_override",
          ),
          isTrue,
        );
        await upgraded.close();
      },
    );

    test("upgrades v5 workspace database to include duration_ms", () async {
      sqfliteFfiInit();
      final String dbPath = p.join(tempDirectory.path, "obs_clipshow.db");
      final Database legacy = await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 5,
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
              CREATE TABLE saved_tags (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL UNIQUE COLLATE NOCASE
              );
            """);
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
              CREATE TABLE ignored_folders (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                relative_path TEXT NOT NULL UNIQUE
              );
            """);
          },
        ),
      );
      await legacy.close();

      final AppDatabase appDatabase = AppDatabase();
      final Workspace workspace = Workspace(rootPath: tempDirectory.path);
      final Database upgraded = await appDatabase.openForWorkspace(workspace);
      final List<Map<String, Object?>> masterColumns = await upgraded.rawQuery(
        "PRAGMA table_info(master_media_files);",
      );
      expect(
        masterColumns.any(
          (Map<String, Object?> row) => row["name"] == "duration_ms",
        ),
        isTrue,
      );
      await upgraded.close();
    });

    test(
      "supports workspace settings, OBS singleton, and webhook list",
      () async {
        final AppDatabase appDatabase = AppDatabase();
        final Workspace workspace = Workspace(rootPath: tempDirectory.path);
        final database = await appDatabase.openForWorkspace(workspace);
        final MediaRepository repository = MediaRepository(database);

        await repository.saveTelestratorDefaults(
          const TelestratorDefaults(
            colorOneArgb: 0xFF111111,
            colorTwoArgb: 0xFF222222,
            colorThreeArgb: 0xFF333333,
            brushSize: 10,
            enabledByDefault: true,
          ),
        );
        await repository.saveDecoderConfig(
          const DecoderConfig(
            enabledProfiles: <DecoderProfile>[DecoderProfile.vdpau],
          ),
        );
        await repository.saveMdkLogVerbosity(MdkLogVerbosity.error);
        await repository.saveFvpLogVerbosity(FvpLogVerbosity.info);
        await repository.saveObsSceneSwitchConfig(
          const ObsSceneSwitchConfig(
            enabled: true,
            serverAddress: "10.0.0.20",
            port: 4456,
            password: "pw",
            videoScene: "video",
            faceScene: "face",
            captureScene: "Cap",
          ),
        );
        await repository.saveObsSceneSwitchConfig(
          const ObsSceneSwitchConfig(
            enabled: false,
            serverAddress: "10.0.0.30",
            port: 4457,
            password: "pw2",
            videoScene: "video2",
            faceScene: "face2",
            captureScene: "",
          ),
        );

        await repository.addWebhookSceneSwitchConfig(
          const WebhookSceneSwitchConfig(
            id: 0,
            name: "wh1",
            enabled: true,
            url: "https://example.com/a",
            method: WebhookMethod.post,
            getQueryParamName: "scene",
            postBodyType: WebhookPostBodyType.json,
            sceneKey: "scene",
          ),
        );
        await repository.addWebhookSceneSwitchConfig(
          const WebhookSceneSwitchConfig(
            id: 0,
            name: "wh2",
            enabled: false,
            url: "https://example.com/b",
            method: WebhookMethod.get,
            getQueryParamName: "s",
            postBodyType: WebhookPostBodyType.form,
            sceneKey: "k",
          ),
        );

        await repository.addIgnoredFolder("20260713");
        await repository.addIgnoredFolder("nested/day2");

        final WorkspaceSettingsBundle settings = await repository
            .loadWorkspaceSettings();
        expect(settings.telestratorDefaults.brushSize, 10);
        expect(
          settings.decoderConfig.enabledProfiles.first,
          DecoderProfile.vdpau,
        );
        expect(settings.mdkLogVerbosity, MdkLogVerbosity.error);
        expect(settings.fvpLogVerbosity, FvpLogVerbosity.info);
        expect(settings.obsSceneSwitchConfig, isNotNull);
        expect(settings.obsSceneSwitchConfig!.serverAddress, "10.0.0.30");
        expect(settings.obsSceneSwitchConfig!.enabled, isFalse);
        expect(settings.obsSceneSwitchConfig!.captureScene, "");
        expect(
          settings.capturePathsSettings.recordingRelativeDir,
          CapturePathsSettings.defaultRecordingRelativeDir,
        );
        expect(settings.webhookSceneSwitchConfigs, hasLength(2));
        expect(settings.webhookSceneSwitchConfigs.first.enabled, isTrue);
        expect(settings.webhookSceneSwitchConfigs.last.enabled, isFalse);
        expect(settings.ignoredFolders, contains("20260713"));
        expect(settings.pauseIngestScanDuringPreview, isTrue);

        await repository.savePauseIngestScanDuringPreview(false);
        expect(
          (await repository.loadWorkspaceSettings()).pauseIngestScanDuringPreview,
          isFalse,
        );

        await repository.saveObsSceneSwitchConfig(null);
        final WorkspaceSettingsBundle disabled = await repository
            .loadWorkspaceSettings();
        expect(disabled.obsSceneSwitchConfig, isNull);

        await database.close();
      },
    );

    test(
      "deletes tag row when it is no longer attached to any media",
      () async {
        final AppDatabase appDatabase = AppDatabase();
        final Workspace workspace = Workspace(rootPath: tempDirectory.path);
        final database = await appDatabase.openForWorkspace(workspace);
        final MediaRepository repository = MediaRepository(database);

        await repository.upsertMasterMedia(
          filePath: "one.mp4",
          fileName: "one.mp4",
          fileSizeBytes: 1000,
          modifiedAtMs: 1000,
          createdAtMs: 1000,
        );
        await repository.upsertMasterMedia(
          filePath: "two.mp4",
          fileName: "two.mp4",
          fileSizeBytes: 1200,
          modifiedAtMs: 1100,
          createdAtMs: 1100,
        );
        final List<MasterMediaFile> media = await repository.listAll();
        final MasterMediaFile first = media.firstWhere(
          (MasterMediaFile item) => item.filePath == "one.mp4",
        );
        final MasterMediaFile second = media.firstWhere(
          (MasterMediaFile item) => item.filePath == "two.mp4",
        );
        await repository.addTagToMedia(
          mediaType: MediaListItemType.master,
          mediaId: first.id,
          tag: "Day 3",
        );
        await repository.addTagToMedia(
          mediaType: MediaListItemType.master,
          mediaId: second.id,
          tag: "Day 3",
        );
        expect(await repository.listAllTags(), contains("Day 3"));

        await repository.removeTagFromMedia(
          mediaType: MediaListItemType.master,
          mediaId: first.id,
          tag: "Day 3",
        );
        expect(await repository.listAllTags(), contains("Day 3"));

        await repository.removeTagFromMedia(
          mediaType: MediaListItemType.master,
          mediaId: second.id,
          tag: "Day 3",
        );
        expect(await repository.listAllTags(), isNot(contains("Day 3")));

        await database.close();
      },
    );
  });
}
