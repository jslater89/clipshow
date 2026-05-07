import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:path/path.dart" as p;

import "package:obs_clipshow/src/data/app_database.dart";
import "package:obs_clipshow/src/data/media_repository.dart";
import "package:obs_clipshow/src/media/workspace.dart";

void main() {
  group("MediaRepository", () {
    late Directory tempDirectory;

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp("obs_clipshow_test_");
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
  });
}
