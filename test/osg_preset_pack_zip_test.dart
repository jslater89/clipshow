import "dart:io";
import "dart:typed_data";

import "package:flutter_test/flutter_test.dart";

import "package:obs_clipshow/src/osg/osg_models.dart";
import "package:obs_clipshow/src/osg/osg_preset_pack_zip.dart";

void main() {
  test("OSG preset pack ZIP round trip (JSON only)", () async {
    final Directory dir = Directory.systemTemp.createTempSync("osg_pack_test");
    try {
      final OsgWorkspaceConfig original = OsgWorkspaceConfig(
        presets: List<OsgPreset>.generate(
          5,
          (_) => OsgPreset.empty(),
        ),
      );
      final List<int> zipBytes = buildOsgPresetPackZip(
        workspaceRoot: dir.path,
        config: original,
      );
      expect(zipBytes.isNotEmpty, true);
      final OsgPresetPackImportResult r = await importOsgPresetPackFromZipBytes(
        workspaceRoot: dir.path,
        zipBytes: Uint8List.fromList(zipBytes),
      );
      expect(r.ok, true);
      expect(r.config.workspacePresets.length, 5);
    } finally {
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    }
  });
}
