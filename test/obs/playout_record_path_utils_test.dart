import "package:flutter_test/flutter_test.dart";
import "package:obs_clipshow/src/obs/playout_record_path_utils.dart";
import "package:obs_clipshow/src/workspace/workspace_settings.dart";

void main() {
  group("PlayoutRecordPathUtils", () {
    test("normalized dirs use defaults when empty", () {
      const PlayoutRecordPathsSettings empty = PlayoutRecordPathsSettings(
        stagingRelativeDir: "",
        outputRelativeDir: "",
      );
      expect(
        PlayoutRecordPathUtils.normalizedStagingDir(
          workspaceAbsolute: "/ws",
          settings: empty,
        ),
        "/ws/recordings/export",
      );
      expect(
        PlayoutRecordPathUtils.normalizedOutputDir(
          workspaceAbsolute: "/ws",
          settings: empty,
        ),
        "/ws/export",
      );
    });

    test("isOutputInsideStagingTree detects nesting", () {
      expect(
        PlayoutRecordPathUtils.isOutputInsideStagingTree(
          stagingDirAbsolute: "/ws/recordings/export",
          outputDirAbsolute: "/ws/recordings/export",
        ),
        isTrue,
      );
      expect(
        PlayoutRecordPathUtils.isOutputInsideStagingTree(
          stagingDirAbsolute: "/ws/recordings/export",
          outputDirAbsolute: "/ws/recordings/export/done",
        ),
        isTrue,
      );
      expect(
        PlayoutRecordPathUtils.isOutputInsideStagingTree(
          stagingDirAbsolute: "/ws/recordings/export",
          outputDirAbsolute: "/ws/export",
        ),
        isFalse,
      );
    });
  });
}
