import "package:flutter_test/flutter_test.dart";

import "package:obs_clipshow/src/osg/osg_key_color_suggester.dart";
import "package:obs_clipshow/src/osg/osg_mode_key_color.dart";
import "package:obs_clipshow/src/osg/osg_models.dart";

void main() {
  group("analyzeOsgKeyColor", () {
    test("flags nearby solid fill as conflict", () {
      const int key = 0xFF00B140;
      final List<OsgRgb> forbidden = <OsgRgb>[
        OsgRgb.fromArgb(0xFF00B150),
      ];
      final OsgKeyColorAnalysis analysis = analyzeOsgKeyColor(
        keyColorArgb: key,
        forbidden: forbidden,
      );
      expect(analysis.isSafe, isFalse);
      expect(analysis.conflicts, isNotEmpty);
    });

    test("accepts key far from forbidden palette", () {
      const int key = 0xFF00B140;
      final List<OsgRgb> forbidden = <OsgRgb>[
        OsgRgb.fromArgb(0xFF2D2D2D),
        OsgRgb.fromArgb(0xFFFFFFFF),
      ];
      final OsgKeyColorAnalysis analysis = analyzeOsgKeyColor(
        keyColorArgb: key,
        forbidden: forbidden,
      );
      expect(analysis.isSafe, isTrue);
      expect(analysis.conflicts, isEmpty);
    });
  });

  group("osgPresetHasColorKeyUnfriendlyTransparency", () {
    test("flags partial layer opacity", () {
      final OsgPreset preset = OsgPreset.empty().copyWith(
        layerOpacity: 0.8,
        visibilityEnterDurationMs: 0,
        visibilityExitDurationMs: 0,
      );
      expect(osgPresetHasColorKeyUnfriendlyTransparency(preset), isTrue);
    });

    test("flags fade durations", () {
      final OsgPreset preset = OsgPreset.empty().copyWith(
        layerOpacity: 1.0,
        visibilityEnterDurationMs: 240,
        visibilityExitDurationMs: 0,
      );
      expect(osgPresetHasColorKeyUnfriendlyTransparency(preset), isTrue);
    });

    test("accepts fully opaque instant preset", () {
      final OsgPreset preset = OsgPreset(
        enabled: false,
        templateRelativePath: "",
        frame: OsgNormRect.unit,
        slots: const <OsgSlot>[],
        layerOpacity: 1.0,
        visibilityEnterDurationMs: 0,
        visibilityExitDurationMs: 0,
      );
      expect(osgPresetHasColorKeyUnfriendlyTransparency(preset), isFalse);
    });
  });

  group("suggestOsgModeKeyColor", () {
    test("picks safe candidate for dark presets", () async {
      final OsgWorkspaceConfig config = OsgWorkspaceConfig(
        presets: <OsgPreset>[
          OsgPreset.empty().copyWith(
            enabled: true,
            templateBackgroundKind: OsgTemplateBackgroundKind.solid,
            templateSolidArgb: 0xFF2D2D2D,
          ),
          OsgPreset.empty(),
          OsgPreset.empty(),
          OsgPreset.empty(),
          OsgPreset.empty(),
        ],
      );
      final OsgKeyColorSuggestion suggestion = await suggestOsgModeKeyColor(
        config: config,
        workspaceRoot: "",
      );
      expect(suggestion.analysis.isSafe, isTrue);
      expect(
        osgKeyColorIsSafe(
          suggestion.suggestedKeyColorArgb,
          <OsgRgb>[OsgRgb.fromArgb(0xFF2D2D2D)],
        ),
        isTrue,
      );
    });
  });
}
