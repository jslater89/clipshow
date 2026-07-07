import "package:flutter_test/flutter_test.dart";

import "package:obs_clipshow/src/osg/osg_bake_models.dart";
import "package:obs_clipshow/src/osg/osg_graphic_export_models.dart";
import "package:obs_clipshow/src/osg/osg_models.dart";

void main() {
  group("osgGraphicExportFrameCanvasPx", () {
    test("scales normalized frame to canvas pixels", () {
      const OsgNormRect frame = OsgNormRect(
        x: 0.1,
        y: 0.75,
        width: 0.35,
        height: 0.12,
      );
      const PlayoutOutputSize canvas = PlayoutOutputSize(
        width: 1920,
        height: 1080,
      );
      expect(
        osgGraphicExportFrameCanvasPx(frameNorm: frame, canvas: canvas),
        <String, int>{"x": 192, "y": 810, "width": 672, "height": 130},
      );
    });
  });

  group("osgGraphicExportSlideDistanceCanvasPx", () {
    test("horizontal motion uses frame width", () {
      expect(
        osgGraphicExportSlideDistanceCanvasPx(
          motion: OsgPresetVisibilityMotion.right,
          slideDistanceNorm: 1.0,
          frameWidthPx: 400,
          frameHeightPx: 100,
        ),
        400,
      );
    });

    test("vertical motion uses frame height", () {
      expect(
        osgGraphicExportSlideDistanceCanvasPx(
          motion: OsgPresetVisibilityMotion.bottom,
          slideDistanceNorm: 0.5,
          frameWidthPx: 400,
          frameHeightPx: 200,
        ),
        100,
      );
    });

    test("none motion is zero", () {
      expect(
        osgGraphicExportSlideDistanceCanvasPx(
          motion: OsgPresetVisibilityMotion.none,
          slideDistanceNorm: 1.0,
          frameWidthPx: 400,
          frameHeightPx: 200,
        ),
        0,
      );
    });
  });

  group("osgGraphicExportCueTimingBlock", () {
    test("resolves anchors and animation bounds", () {
      final OsgPreset preset = OsgPreset.empty().copyWith(
        visibilityEnterDurationMs: 300,
        visibilityExitDurationMs: 200,
      );
      const OsgBakeCue cue = OsgBakeCue(
        slot: OsgPresetSlot.preset1,
        start: OsgBakeAnchor.clipStart(),
        end: OsgBakeAnchor.offsetFromEndMs(2000),
      );
      final Map<String, Object?> block = osgGraphicExportCueTimingBlock(
        cue: cue,
        preset: preset,
        clipDurationMs: 12000,
      );
      expect(block["valid"], isTrue);
      expect(block["inResolvedMs"], 0);
      expect(block["outResolvedMs"], 10000);
      expect(block["enterAnimationStartMs"], -300);
      expect(block["exitAnimationEndMs"], 10200);
      expect(block["in"], cue.start.toJson());
      expect(block["out"], cue.end.toJson());
    });

    test("marks degenerate cues invalid", () {
      const OsgBakeCue cue = OsgBakeCue(
        slot: OsgPresetSlot.preset1,
        start: OsgBakeAnchor.absoluteMs(5000),
        end: OsgBakeAnchor.absoluteMs(4000),
      );
      final Map<String, Object?> block = osgGraphicExportCueTimingBlock(
        cue: cue,
        preset: OsgPreset.empty(),
        clipDurationMs: 10000,
      );
      expect(block["valid"], isFalse);
      expect(block.containsKey("inResolvedMs"), isFalse);
    });
  });

  group("buildOsgGraphicExportManifest", () {
    test("includes slot keys and motion blocks", () {
      final OsgPreset preset = OsgPreset.empty().copyWith(
        enabled: true,
        visibilityEnterMotion: OsgPresetVisibilityMotion.bottom,
        visibilityEnterSlideDistanceNorm: 1.0,
        frame: const OsgNormRect(x: 0, y: 0.8, width: 1, height: 0.2),
      );
      final List<OsgPreset> presets = <OsgPreset>[
        preset,
        OsgPreset.empty(),
        OsgPreset.empty(),
        OsgPreset.empty(),
        OsgPreset.empty(),
      ];
      const OsgBakeRecipe recipe = OsgBakeRecipe(
        id: 1,
        name: "Test Recipe",
        cues: <OsgBakeCue>[
          OsgBakeCue(
            slot: OsgPresetSlot.preset1,
            start: OsgBakeAnchor.clipStart(),
            end: OsgBakeAnchor.clipEnd(),
          ),
        ],
      );
      final Map<String, Object?> manifest = buildOsgGraphicExportManifest(
        recipe: recipe,
        canvas: PlayoutOutputSize.fallback,
        sourceClipDisplayName: "Clip A",
        sourceClipFileName: "game.mp4",
        sourceClipWorkspaceRelativePath: "masters/game.mp4",
        inMs: 0,
        outMs: 10000,
        clipDurationMs: 10000,
        presets: presets,
        semanticTextByTypeId: const <int, String>{},
        annotationsText: "note",
      );
      expect(manifest["schemaVersion"], osgGraphicExportSchemaVersion);
      final Map<String, Object?> sourceClip = Map<String, Object?>.from(
        manifest["sourceClip"]! as Map<Object?, Object?>,
      );
      expect(sourceClip["fileName"], "game.mp4");
      expect(sourceClip["workspaceRelativePath"], "masters/game.mp4");
      expect(manifest.containsKey("osg6"), isTrue);
      final Map<String, Object?> osg6 = Map<String, Object?>.from(
        manifest["osg6"]! as Map<Object?, Object?>,
      );
      expect(osg6["file"], "osg6.png");
      expect(
        (osg6["enter"]! as Map<Object?, Object?>)["slideDistanceCanvasPx"],
        216,
      );
      final List<dynamic> cues = osg6["cues"]! as List<dynamic>;
      expect(cues.length, 1);
    });
  });
}
