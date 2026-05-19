import "package:flutter_test/flutter_test.dart";
import "package:obs_clipshow/src/workspace/ignored_path_utils.dart";

void main() {
  group("IgnoredPathUtils", () {
    test("isPathCoveredByIgnoredFolder matches self and children", () {
      expect(
        IgnoredPathUtils.isPathCoveredByIgnoredFolder(
          relativePath: "recordings/export",
          ignoredFolder: "recordings",
        ),
        isTrue,
      );
      expect(
        IgnoredPathUtils.isPathCoveredByIgnoredFolder(
          relativePath: "recordings",
          ignoredFolder: "recordings",
        ),
        isTrue,
      );
      expect(
        IgnoredPathUtils.isPathCoveredByIgnoredFolder(
          relativePath: "export",
          ignoredFolder: "recordings",
        ),
        isFalse,
      );
    });

    test("isPathCoveredByAnyIgnoredFolder", () {
      expect(
        IgnoredPathUtils.isPathCoveredByAnyIgnoredFolder(
          relativePath: "recordings/export",
          ignoredFolders: <String>["other", "recordings"],
        ),
        isTrue,
      );
    });
  });
}
