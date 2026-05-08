import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:path/path.dart" as p;
import "package:sqflite_common_ffi/sqflite_ffi.dart";

import "package:obs_clipshow/src/data/app_database.dart";
import "package:obs_clipshow/src/data/media_repository.dart";
import "package:obs_clipshow/src/media/master_media_file.dart";
import "package:obs_clipshow/src/media/media_list_item.dart";
import "package:obs_clipshow/src/media/workspace.dart";

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

      const String filePath = "/tmp/highlight.mp4";
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

    test("second upsert keeps stored media issue fields", () async {
      final AppDatabase appDatabase = AppDatabase();
      final Workspace workspace = Workspace(rootPath: tempDirectory.path);
      final database = await appDatabase.openForWorkspace(workspace);
      final MediaRepository repository = MediaRepository(database);

      const String filePath = "/tmp/fragile.mp4";
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

      const String filePath = "/tmp/source.mp4";
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

    test("deletes tag row when it is no longer attached to any media", () async {
      final AppDatabase appDatabase = AppDatabase();
      final Workspace workspace = Workspace(rootPath: tempDirectory.path);
      final database = await appDatabase.openForWorkspace(workspace);
      final MediaRepository repository = MediaRepository(database);

      await repository.upsertMasterMedia(
        filePath: "/tmp/one.mp4",
        fileName: "one.mp4",
        fileSizeBytes: 1000,
        modifiedAtMs: 1000,
        createdAtMs: 1000,
      );
      await repository.upsertMasterMedia(
        filePath: "/tmp/two.mp4",
        fileName: "two.mp4",
        fileSizeBytes: 1200,
        modifiedAtMs: 1100,
        createdAtMs: 1100,
      );
      final List<MasterMediaFile> media = await repository.listAll();
      final MasterMediaFile first = media.firstWhere(
        (MasterMediaFile item) => item.filePath == "/tmp/one.mp4",
      );
      final MasterMediaFile second = media.firstWhere(
        (MasterMediaFile item) => item.filePath == "/tmp/two.mp4",
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
    });
  });
}
