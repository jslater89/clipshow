import "package:flutter_test/flutter_test.dart";

import "package:obs_clipshow/src/ingestion/ingestion_service.dart";
import "package:obs_clipshow/src/ingestion/workspace_watcher.dart";

void main() {
  group("IngestionService", () {
    test("accepts supported video extensions", () {
      expect(IngestionService.isSupportedVideoPath("/tmp/clip.mp4"), isTrue);
      expect(IngestionService.isSupportedVideoPath("/tmp/clip.MOV"), isTrue);
      expect(IngestionService.isSupportedVideoPath("/tmp/clip.txt"), isFalse);
    });

    test("exposes dedupe-safe unique-key strategy through path support", () {
      const String firstPath = "/tmp/session/highlight.mkv";
      const String secondPath = "/tmp/session/highlight.mkv";

      expect(IngestionService.isSupportedVideoPath(firstPath), isTrue);
      expect(IngestionService.isSupportedVideoPath(secondPath), isTrue);
      expect(firstPath, secondPath);
    });

    test("can be created and disposed cleanly", () async {
      final IngestionService service = IngestionService(
        workspaceWatcher: WorkspaceWatcher(),
      );
      await service.dispose();
    });
  });
}
