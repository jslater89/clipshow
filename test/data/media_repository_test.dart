import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:path/path.dart" as p;
import "package:sqflite_common_ffi/sqflite_ffi.dart";

import "package:obs_clipshow/src/data/app_database.dart";
import "package:obs_clipshow/src/data/media_repository.dart";
import "package:obs_clipshow/src/media/master_media_file.dart";
import "package:obs_clipshow/src/media/media_clip.dart";
import "package:obs_clipshow/src/media/media_list_item.dart";
import "package:obs_clipshow/src/media/tag_set.dart";
import "package:obs_clipshow/src/media/workspace.dart";
import "package:obs_clipshow/src/osg/osg_mode_key_color.dart";
import "package:obs_clipshow/src/osg/osg_models.dart";
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

    test("createClip copies semantic types from master tags", () async {
      final AppDatabase appDatabase = AppDatabase();
      final Workspace workspace = Workspace(rootPath: tempDirectory.path);
      final Database database = await appDatabase.openForWorkspace(workspace);
      final MediaRepository repository = MediaRepository(database);

      const String filePath = "typed-source.mp4";
      await repository.upsertMasterMedia(
        filePath: filePath,
        fileName: "typed-source.mp4",
        fileSizeBytes: 3000,
        modifiedAtMs: 3000,
        createdAtMs: 1000,
      );
      final MasterMediaFile master = (await repository.listAll()).single;
      final int semanticTypeId = await repository.insertTagSemanticType(
        name: "Episode",
        iconCodePoint: 0xe047,
      );
      await repository.addTagToMedia(
        mediaType: MediaListItemType.master,
        mediaId: master.id,
        tag: "E01",
        semanticTypeId: semanticTypeId,
      );

      await repository.createClip(
        masterMediaId: master.id,
        inMs: 1000,
        outMs: 4000,
      );
      final MediaClip clip = (await repository.listClips()).single;
      final Map<String, List<MediaTagAttachment>> byKey =
          await repository.listMediaTagAttachmentsForItems(
        <MediaListItem>[MediaListItem.clip(clip)],
      );
      final List<MediaTagAttachment> clipTags =
          byKey["c:${clip.id}"] ?? <MediaTagAttachment>[];
      final MediaTagAttachment e01 = clipTags.firstWhere(
        (MediaTagAttachment a) => a.tagName == "E01",
      );
      expect(e01.semanticTypeId, semanticTypeId);
      expect(e01.semanticTypeName, "Episode");

      await database.close();
    });

    test("filterItems loads tags in one batch and matches AND semantics", () async {
      final AppDatabase appDatabase = AppDatabase();
      final Workspace workspace = Workspace(rootPath: tempDirectory.path);
      final Database database = await appDatabase.openForWorkspace(workspace);
      final MediaRepository repository = MediaRepository(database);

      await repository.upsertMasterMedia(
        filePath: "a.mp4",
        fileName: "a.mp4",
        fileSizeBytes: 1000,
        modifiedAtMs: 1000,
        createdAtMs: 1000,
      );
      await repository.upsertMasterMedia(
        filePath: "b.mp4",
        fileName: "b.mp4",
        fileSizeBytes: 2000,
        modifiedAtMs: 2000,
        createdAtMs: 1000,
      );
      final List<MasterMediaFile> masters = await repository.listAll();
      final MasterMediaFile first = masters.firstWhere(
        (MasterMediaFile m) => m.filePath == "a.mp4",
      );
      final MasterMediaFile second = masters.firstWhere(
        (MasterMediaFile m) => m.filePath == "b.mp4",
      );
      await repository.addTagToMedia(
        mediaType: MediaListItemType.master,
        mediaId: first.id,
        tag: "Day 3",
      );
      await repository.addTagToMedia(
        mediaType: MediaListItemType.master,
        mediaId: first.id,
        tag: "Stage 5",
      );
      await repository.addTagToMedia(
        mediaType: MediaListItemType.master,
        mediaId: second.id,
        tag: "Day 3",
      );

      final List<MediaListItem> andFilter = await repository.filterItems(
        requiredTags: <String>{"Day 3", "Stage 5"},
        untaggedOnly: false,
      );
      expect(andFilter, hasLength(1));
      expect(andFilter.single.master!.filePath, "a.mp4");

      final List<MediaListItem> dayOnly = await repository.filterItems(
        requiredTags: <String>{"Day 3"},
        untaggedOnly: false,
      );
      expect(dayOnly, hasLength(2));

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

    test("persists annotations for masters and clips", () async {
      sqfliteFfiInit();
      final AppDatabase appDatabase = AppDatabase();
      final Workspace workspace = Workspace(rootPath: tempDirectory.path);
      final Database database = await appDatabase.openForWorkspace(workspace);
      final MediaRepository repository = MediaRepository(database);

      await repository.upsertMasterMedia(
        filePath: "one.mp4",
        fileName: "one.mp4",
        fileSizeBytes: 123,
        modifiedAtMs: 100,
        createdAtMs: 90,
        durationMs: 1000,
      );
      final MasterMediaFile master = (await repository.listAll()).single;
      final int clipId = await repository.createClip(
        masterMediaId: master.id,
        inMs: 1000,
        outMs: 4000,
      );
      final MediaClip clip = (await repository.listClips()).firstWhere(
        (MediaClip c) => c.id == clipId,
      );

      await repository.setMediaAnnotations(
        mediaType: MediaListItemType.master,
        mediaId: master.id,
        annotations: "Score: 3-2\nOvertime",
      );
      await repository.setMediaAnnotations(
        mediaType: MediaListItemType.clip,
        mediaId: clip.id,
        annotations: "Clip note",
      );

      final MasterMediaFile updatedMaster = (await repository.listAll()).single;
      final MediaClip updatedClip = (await repository.listClips()).single;
      expect(updatedMaster.annotations, contains("Score"));
      expect(updatedClip.annotations, "Clip note");

      await repository.setMediaAnnotations(
        mediaType: MediaListItemType.clip,
        mediaId: clip.id,
        annotations: "   ",
      );
      final MediaClip clearedClip = (await repository.listClips()).single;
      expect(clearedClip.annotations, isNull);

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
            platform: DecoderPlatform.linux,
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
            osgScene: "OSG Scene",
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
            osgScene: "",
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
        expect(
          settings.playoutRecordPathsSettings.stagingRelativeDir,
          PlayoutRecordPathsSettings.defaultStagingRelativeDir,
        );
        expect(
          settings.playoutRecordPathsSettings.outputRelativeDir,
          PlayoutRecordPathsSettings.defaultOutputRelativeDir,
        );
        expect(settings.webhookSceneSwitchConfigs, hasLength(2));
        expect(settings.webhookSceneSwitchConfigs.first.enabled, isTrue);
        expect(settings.webhookSceneSwitchConfigs.last.enabled, isFalse);
        expect(settings.ignoredFolders, contains("20260713"));
        expect(settings.pauseIngestScanDuringPreview, isTrue);
        expect(
          settings.ingestProbeConcurrency,
          IngestionConcurrencyDefaults.probeDefault,
        );
        expect(
          settings.ingestThumbnailConcurrency,
          IngestionConcurrencyDefaults.thumbnailDefault,
        );
        expect(
          settings.defaultClipVolume,
          PlaybackVolumeDefaults.defaultVolume,
        );
        expect(
          settings.osgModeKeyColorArgb,
          OsgModeKeyColorSettings.defaultKeyColorArgb,
        );

        await repository.saveOsgModeKeyColorArgb(0xFF112233);
        expect(
          (await repository.loadWorkspaceSettings()).osgModeKeyColorArgb,
          0xFF112233,
        );

        await repository.savePauseIngestScanDuringPreview(false);
        expect(
          (await repository.loadWorkspaceSettings()).pauseIngestScanDuringPreview,
          isFalse,
        );

        await repository.saveIngestProbeConcurrency(12);
        await repository.saveIngestThumbnailConcurrency(4);
        final WorkspaceSettingsBundle ingestTuned =
            await repository.loadWorkspaceSettings();
        expect(ingestTuned.ingestProbeConcurrency, 12);
        expect(ingestTuned.ingestThumbnailConcurrency, 4);

        await repository.saveIngestProbeConcurrency(999);
        await repository.saveIngestThumbnailConcurrency(0);
        final WorkspaceSettingsBundle clamped =
            await repository.loadWorkspaceSettings();
        expect(
          clamped.ingestProbeConcurrency,
          IngestionConcurrencyDefaults.probeMax,
        );
        expect(
          clamped.ingestThumbnailConcurrency,
          IngestionConcurrencyDefaults.thumbnailMin,
        );

        await repository.saveDefaultClipVolume(0.4);
        final WorkspaceSettingsBundle volumeTuned =
            await repository.loadWorkspaceSettings();
        expect(volumeTuned.defaultClipVolume, closeTo(0.4, 1e-9));

        await repository.saveDefaultClipVolume(2.0);
        expect(
          (await repository.loadWorkspaceSettings()).defaultClipVolume,
          PlaybackVolumeDefaults.max,
        );

        await repository.saveDefaultClipVolume(-1.0);
        expect(
          (await repository.loadWorkspaceSettings()).defaultClipVolume,
          PlaybackVolumeDefaults.min,
        );

        await repository.saveObsSceneSwitchConfig(null);
        final WorkspaceSettingsBundle disabled = await repository
            .loadWorkspaceSettings();
        expect(disabled.obsSceneSwitchConfig, isNull);

        await repository.savePlayoutRecordPathsSettings(
          const PlayoutRecordPathsSettings(
            stagingRelativeDir: "custom/staging",
            outputRelativeDir: "custom/out",
          ),
        );
        final List<String> ignoredAfterPlayout =
            await repository.listIgnoredFolders();
        expect(ignoredAfterPlayout, contains("custom/staging"));
        expect(ignoredAfterPlayout, contains("custom/out"));

        await repository.addIgnoredFolder("recordings");
        await repository.savePlayoutRecordPathsSettings(
          const PlayoutRecordPathsSettings(
            stagingRelativeDir: "recordings/export",
            outputRelativeDir: "export",
          ),
        );
        final List<String> ignoredAfterNestedPlayout =
            await repository.listIgnoredFolders();
        expect(ignoredAfterNestedPlayout, contains("recordings"));
        expect(ignoredAfterNestedPlayout, isNot(contains("recordings/export")));
        expect(ignoredAfterNestedPlayout, contains("export"));

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

    test("upgrades v7 workspace database to v8 tag semantics and OSG settings",
        () async {
      sqfliteFfiInit();
      final String dbPath = p.join(tempDirectory.path, "obs_clipshow.db");
      final Database legacy = await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 7,
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
                duration_ms INTEGER,
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
                obs_capture_scene TEXT,
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
      final List<Map<String, Object?>> semTable = await upgraded.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='tag_semantic_types'",
      );
      expect(semTable, isNotEmpty);
      final List<Map<String, Object?>> mtCols = await upgraded.rawQuery(
        "PRAGMA table_info(media_tags);",
      );
      expect(
        mtCols.any((Map<String, Object?> r) => r["name"] == "semantic_type_id"),
        isTrue,
      );

      final MediaRepository repository = MediaRepository(upgraded);
      final WorkspaceSettingsBundle settings =
          await repository.loadWorkspaceSettings();
      expect(settings.playoutOutputSize.width, PlayoutOutputSize.fallback.width);
      await repository.savePlayoutOutputSize(
        const PlayoutOutputSize(width: 1280, height: 720),
      );
      final WorkspaceSettingsBundle after =
          await repository.loadWorkspaceSettings();
      expect(after.playoutOutputSize.width, 1280);
      expect(after.playoutOutputSize.height, 720);

      final int typeId = await repository.insertTagSemanticType(name: "Name");
      await repository.upsertMasterMedia(
        filePath: "x.mp4",
        fileName: "x.mp4",
        fileSizeBytes: 100,
        modifiedAtMs: 100,
        createdAtMs: 100,
      );
      final MasterMediaFile master = (await repository.listAll()).single;
      await repository.addTagToMedia(
        mediaType: MediaListItemType.master,
        mediaId: master.id,
        tag: "Jay",
      );
      final List<Map<String, Object?>> mtRows = await upgraded.rawQuery(
        """
        SELECT media_tags.id
        FROM media_tags
        JOIN tags ON tags.id = media_tags.tag_id
        WHERE media_tags.media_type = 'master'
          AND media_tags.media_id = ?
          AND tags.name = ? COLLATE NOCASE
        """,
        <Object?>[master.id, "Jay"],
      );
      expect(mtRows, isNotEmpty);
      final int mediaTagId = mtRows.single["id"]! as int;
      await repository.setMediaTagSemanticType(
        mediaTagId: mediaTagId,
        semanticTypeId: typeId,
      );
      final MediaListItem item = MediaListItem.master(master);
      final Map<String, List<MediaTagAttachment>> map =
          await repository.listMediaTagAttachmentsForItems(<MediaListItem>[item]);
      final List<MediaTagAttachment> list = map[item.stableKey]!;
      final MediaTagAttachment jay = list.firstWhere(
        (MediaTagAttachment a) => a.tagName == "Jay",
      );
      expect(jay.semanticTypeId, typeId);

      await upgraded.close();
    });

    test("upgrades v8 workspace to add saved_tags.semantic_type_id column",
        () async {
      sqfliteFfiInit();
      final String dbPath = p.join(tempDirectory.path, "obs_clipshow.db");
      final Database legacy = await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 8,
          onCreate: (Database db, int version) async {
            await db.execute("""
              CREATE TABLE tag_semantic_types (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL UNIQUE COLLATE NOCASE,
                icon_code_point INTEGER
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
                semantic_type_id INTEGER,
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
          },
        ),
      );
      await legacy.close();

      final AppDatabase appDatabase = AppDatabase();
      final Workspace workspace = Workspace(rootPath: tempDirectory.path);
      final Database upgraded = await appDatabase.openForWorkspace(workspace);
      final List<Map<String, Object?>> stCols = await upgraded.rawQuery(
        "PRAGMA table_info(saved_tags);",
      );
      expect(
        stCols.any((Map<String, Object?> r) => r["name"] == "semantic_type_id"),
        isTrue,
      );
      await upgraded.close();
    });

    test("creates tag sets and attaches tags for OSG Mode", () async {
      final AppDatabase appDatabase = AppDatabase();
      final Workspace workspace = Workspace(rootPath: tempDirectory.path);
      final database = await appDatabase.openForWorkspace(workspace);
      final MediaRepository repository = MediaRepository(database);

      final TagSet tagSet = await repository.createTagSet("Lower Third A");
      await repository.addTagToMedia(
        mediaType: MediaListItemType.tagSet,
        mediaId: tagSet.id,
        tag: "Player One",
      );
      await repository.setMediaAnnotations(
        mediaType: MediaListItemType.tagSet,
        mediaId: tagSet.id,
        annotations: "Notes for annotation slots",
      );

      final List<TagSet> listed = await repository.listTagSets();
      expect(listed, hasLength(1));
      expect(listed.single.name, "Lower Third A");
      expect(
        await repository.resolveSemanticTagForMedia(
          mediaType: MediaListItemType.tagSet,
          mediaId: tagSet.id,
          semanticTypeId: 99,
        ),
        isNull,
      );

      final Map<String, List<MediaTagAttachment>> attachments =
          await repository.listMediaTagAttachmentsForTagSets(<int>[tagSet.id]);
      // "Tag Set" is auto-attached by createTagSet as a system tag, alongside
      // the explicitly-added "Player One" tag.
      expect(attachments["ts:${tagSet.id}"], hasLength(2));
      expect(
        attachments["ts:${tagSet.id}"]!.map(
          (MediaTagAttachment a) => a.tagName,
        ),
        containsAll(<String>["Player One", MediaRepository.tagSetTag]),
      );

      await repository.saveOsgModeQuickSlotTagSetIds(<int?>[tagSet.id, null]);
      final List<int?> slots = await repository.loadOsgModeQuickSlotTagSetIds();
      expect(slots.first, tagSet.id);

      await repository.deleteTagSet(tagSet.id);
      expect(await repository.listTagSets(), isEmpty);

      await database.close();
    });
  });
}
