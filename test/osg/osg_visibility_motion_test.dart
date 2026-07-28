import "package:flutter_test/flutter_test.dart";

import "package:obs_clipshow/src/osg/osg_models.dart";
import "package:obs_clipshow/src/osg/osg_visibility_motion.dart";

void main() {
  group("effectiveVisibilityFadeDurationMs", () {
    test("fade-only motion uses full transition", () {
      expect(
        OsgPreset.effectiveVisibilityFadeDurationMs(
          fadeMs: 100,
          transitionMs: 500,
          motion: OsgPresetVisibilityMotion.none,
        ),
        500,
      );
    });

    test("slide motion caps fade at transition", () {
      expect(
        OsgPreset.effectiveVisibilityFadeDurationMs(
          fadeMs: 800,
          transitionMs: 500,
          motion: OsgPresetVisibilityMotion.left,
        ),
        500,
      );
    });
  });

  group("osgVisibilityFadeShown", () {
    test("enter completes fade early", () {
      expect(
        osgVisibilityFadeShown(
          entering: true,
          shown: 0.5,
          fadeMs: 250,
          transitionMs: 500,
        ),
        1.0,
      );
      expect(
        osgVisibilityFadeShown(
          entering: true,
          shown: 0.25,
          fadeMs: 250,
          transitionMs: 500,
        ),
        0.5,
      );
    });

    test("exit completes fade early", () {
      expect(
        osgVisibilityFadeShown(
          entering: false,
          shown: 0.5,
          fadeMs: 250,
          transitionMs: 500,
        ),
        0.0,
      );
      expect(
        osgVisibilityFadeShown(
          entering: false,
          shown: 0.75,
          fadeMs: 250,
          transitionMs: 500,
        ),
        0.5,
      );
    });
  });

  group("osgVisibilityOpacityAndOffset fade vs slide", () {
    test("enter is fully opaque mid-slide when fade is half duration", () {
      final ({double opacity, Offset offset}) vis =
          osgVisibilityOpacityAndOffset(
        entering: true,
        shown: 0.5,
        layerOpacity: 1.0,
        enterMotion: OsgPresetVisibilityMotion.right,
        enterSlideDistanceNorm: 1.0,
        exitMotion: OsgPresetVisibilityMotion.none,
        exitSlideDistanceNorm: 1.0,
        frameWidthPx: 200,
        frameHeightPx: 100,
        enterDurationMs: 500,
        enterFadeDurationMs: 250,
      );
      expect(vis.opacity, 1.0);
      expect(vis.offset.dx, greaterThan(0));
    });

    test("exit is fully transparent mid-slide when fade is half duration", () {
      final ({double opacity, Offset offset}) vis =
          osgVisibilityOpacityAndOffset(
        entering: false,
        shown: 0.5,
        layerOpacity: 1.0,
        enterMotion: OsgPresetVisibilityMotion.none,
        enterSlideDistanceNorm: 1.0,
        exitMotion: OsgPresetVisibilityMotion.left,
        exitSlideDistanceNorm: 1.0,
        frameWidthPx: 200,
        frameHeightPx: 100,
        exitDurationMs: 500,
        exitFadeDurationMs: 250,
      );
      expect(vis.opacity, 0.0);
      expect(vis.offset.dx, isNot(0));
    });

    test("fade-only ignores shorter fade duration field", () {
      final ({double opacity, Offset offset}) shortFadeField =
          osgVisibilityOpacityAndOffset(
        entering: true,
        shown: 0.5,
        layerOpacity: 1.0,
        enterMotion: OsgPresetVisibilityMotion.none,
        enterSlideDistanceNorm: 1.0,
        exitMotion: OsgPresetVisibilityMotion.none,
        exitSlideDistanceNorm: 1.0,
        frameWidthPx: 200,
        frameHeightPx: 100,
        enterDurationMs: 500,
        enterFadeDurationMs: 250,
      );
      final ({double opacity, Offset offset}) matched =
          osgVisibilityOpacityAndOffset(
        entering: true,
        shown: 0.5,
        layerOpacity: 1.0,
        enterMotion: OsgPresetVisibilityMotion.none,
        enterSlideDistanceNorm: 1.0,
        exitMotion: OsgPresetVisibilityMotion.none,
        exitSlideDistanceNorm: 1.0,
        frameWidthPx: 200,
        frameHeightPx: 100,
        enterDurationMs: 500,
        enterFadeDurationMs: 500,
      );
      expect(shortFadeField.opacity, matched.opacity);
      expect(shortFadeField.offset, Offset.zero);
    });
  });

  group("OsgPreset fade duration JSON", () {
    test("missing fade keys default to transition duration", () {
      final Map<String, Object?> json = OsgPreset.empty()
          .copyWith(
            visibilityEnterDurationMs: 400,
            visibilityExitDurationMs: 300,
          )
          .toJson();
      json.remove("visibilityEnterFadeDurationMs");
      json.remove("visibilityExitFadeDurationMs");
      final OsgPreset decoded = OsgPreset.fromJson(json);
      expect(decoded.visibilityEnterFadeDurationMs, 400);
      expect(decoded.visibilityExitFadeDurationMs, 300);
    });

    test("copyWith shortens fade when transition shrinks", () {
      final OsgPreset p = OsgPreset.empty().copyWith(
        visibilityEnterDurationMs: 500,
        visibilityEnterFadeDurationMs: 400,
      );
      final OsgPreset shortened = p.copyWith(visibilityEnterDurationMs: 200);
      expect(shortened.visibilityEnterDurationMs, 200);
      expect(shortened.visibilityEnterFadeDurationMs, 200);
    });
  });
}
