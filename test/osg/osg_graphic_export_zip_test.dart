import "dart:convert";
import "dart:typed_data";

import "package:archive/archive.dart";
import "package:flutter_test/flutter_test.dart";

import "package:obs_clipshow/src/osg/osg_bake_models.dart";
import "package:obs_clipshow/src/osg/osg_graphic_export_models.dart";
import "package:obs_clipshow/src/osg/osg_graphic_export_zip.dart";
import "package:obs_clipshow/src/osg/osg_models.dart";

void main() {
  test("buildOsgGraphicExportZip contains manifest and slot PNGs", () {
    const OsgBakeRecipe recipe = OsgBakeRecipe(
      id: 2,
      name: "Zip Test",
      cues: <OsgBakeCue>[
        OsgBakeCue(
          slot: OsgPresetSlot.preset1,
          start: OsgBakeAnchor.clipStart(),
          end: OsgBakeAnchor.clipEnd(),
        ),
        OsgBakeCue(
          slot: OsgPresetSlot.preset2,
          start: OsgBakeAnchor.absoluteMs(1000),
          end: OsgBakeAnchor.absoluteMs(5000),
        ),
      ],
    );
    final Map<String, Object?> manifest = buildOsgGraphicExportManifest(
      recipe: recipe,
      canvas: PlayoutOutputSize.fallback,
      sourceClipDisplayName: "Clip",
      sourceClipFileName: "clip.mp4",
      sourceClipWorkspaceRelativePath: "video/clip.mp4",
      inMs: 0,
      outMs: 8000,
      clipDurationMs: 8000,
      presets: List<OsgPreset>.generate(5, (_) => OsgPreset.empty()),
      semanticTextByTypeId: const <int, String>{},
      annotationsText: "",
    );
    final Uint8List zipBytes = buildOsgGraphicExportZip(
      manifest: manifest,
      pngBySlot: <OsgPresetSlot, Uint8List>{
        OsgPresetSlot.preset1: Uint8List.fromList(<int>[1, 2, 3]),
        OsgPresetSlot.preset2: Uint8List.fromList(<int>[4, 5, 6]),
      },
    );

    final Archive archive = ZipDecoder().decodeBytes(zipBytes);
    final ArchiveFile? manifestFile = archive.files
        .where((ArchiveFile f) => f.name == osgGraphicExportManifestEntry)
        .firstOrNull;
    expect(manifestFile, isNotNull);
    final Object? decoded = jsonDecode(
      utf8.decode(manifestFile!.content as List<int>),
    );
    expect(decoded, isA<Map<String, dynamic>>());
    expect(
      archive.files.map((ArchiveFile f) => f.name).toList(),
      containsAll(<String>["manifest.json", "osg6.png", "osg7.png"]),
    );
  });
}
