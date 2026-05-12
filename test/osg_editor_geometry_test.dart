import "package:flutter_test/flutter_test.dart";

import "package:obs_clipshow/src/features/osg/osg_editor_geometry.dart";
import "package:obs_clipshow/src/features/osg/osg_editor_pixel_rect.dart";
import "package:obs_clipshow/src/osg/osg_models.dart";

void main() {
  group("osgClampFrame", () {
    test("clamps position and size inside unit square", () {
      final OsgNormRect r = osgClampFrame(
        const OsgNormRect(x: -0.1, y: 0.9, width: 0.5, height: 0.2),
      );
      expect(r.x, greaterThanOrEqualTo(0));
      expect(r.y, greaterThanOrEqualTo(0));
      expect(r.x + r.width, lessThanOrEqualTo(1.0 + 1e-9));
      expect(r.y + r.height, lessThanOrEqualTo(1.0 + 1e-9));
      expect(r.width, greaterThanOrEqualTo(0.05));
      expect(r.height, greaterThanOrEqualTo(0.05));
    });
  });

  group("osgClampSlotBox", () {
    test("keeps slot box inside canvas", () {
      final OsgNormRect r = osgClampSlotBox(
        const OsgNormRect(x: 0.95, y: 0.95, width: 0.5, height: 0.5),
      );
      expect(r.x + r.width, lessThanOrEqualTo(1.0 + 1e-9));
      expect(r.y + r.height, lessThanOrEqualTo(1.0 + 1e-9));
    });
  });

  group("osgClampFrameForPlayout", () {
    test("allows frame to extend roughly half off each axis", () {
      const OsgNormRect r = OsgNormRect(
        x: -0.2,
        y: 0.9,
        width: 0.4,
        height: 0.2,
      );
      final OsgNormRect c = osgClampFrameForPlayout(r);
      expect(c.x, closeTo(-0.2, 1e-9));
      expect(c.y, closeTo(0.9, 1e-9));
      expect(c.width, 0.4);
      expect(c.height, 0.2);
    });
  });

  group("osgClampFrameWithImageAspect", () {
    test("forces normalized w/h ratio from image vs playout aspect", () {
      const double img = 16 / 9;
      const double play = 16 / 9;
      final OsgNormRect r = osgClampFrameWithImageAspect(
        frame: const OsgNormRect(x: 0, y: 0, width: 0.4, height: 0.2),
        imageWidthOverHeight: img,
        playoutAspect: play,
      );
      expect(r.width / r.height, closeTo(1.0, 1e-6));
    });
  });

  group("osg pixel rect helpers", () {
    test("frame canvas pixels round-trip", () {
      const OsgNormRect r = OsgNormRect(
        x: 0.1,
        y: 0.2,
        width: 0.3,
        height: 0.15,
      );
      const int cw = 1920;
      const int ch = 1080;
      final ({int x, int y, int w, int h}) p = osgNormFrameToCanvasPixels(
        r,
        cw,
        ch,
      );
      final OsgNormRect back = osgCanvasPixelsToNormFrame(
        p.x,
        p.y,
        p.w,
        p.h,
        cw,
        ch,
      );
      expect(back.x, closeTo(r.x, 1e-5));
      expect(back.y, closeTo(r.y, 1e-5));
      expect(back.width, closeTo(r.width, 1e-5));
      expect(back.height, closeTo(r.height, 1e-5));
    });

    test("frame canvas pixels round-trip with negative origin", () {
      const OsgNormRect r = OsgNormRect(
        x: -0.05,
        y: 0.75,
        width: 0.5,
        height: 0.2,
      );
      const int cw = 1920;
      const int ch = 1080;
      final ({int x, int y, int w, int h}) p = osgNormFrameToCanvasPixels(
        r,
        cw,
        ch,
      );
      expect(p.x, lessThan(0));
      final OsgNormRect back = osgCanvasPixelsToNormFrame(
        p.x,
        p.y,
        p.w,
        p.h,
        cw,
        ch,
      );
      expect(back.x, closeTo(r.x, 1e-5));
      expect(back.y, closeTo(r.y, 1e-5));
    });
  });

  group("osgSolidTemplatePixelsForFrame", () {
    test("matches empty preset frame on fallback canvas", () {
      final OsgPreset e = OsgPreset.empty();
      expect(e.templateSolidWidthPx, 1920);
      expect(e.templateSolidHeightPx, 270);
      expect(e.templateAspectRatioForFrame, closeTo(1920 / 270, 1e-9));
    });
  });

  group("OsgPreset.templateCornerRadiusPx", () {
    test("scales by shorter frame side and caps at half", () {
      const OsgPreset p = OsgPreset(
        enabled: true,
        templateRelativePath: "",
        frame: OsgNormRect.unit,
        slots: <OsgSlot>[],
        templateCornerRadiusNorm: 0.1,
      );
      expect(p.templateCornerRadiusPx(100, 200), closeTo(10, 1e-9));
      expect(p.templateCornerRadiusPx(300, 100), closeTo(10, 1e-9));
      const OsgPreset pill = OsgPreset(
        enabled: true,
        templateRelativePath: "",
        frame: OsgNormRect.unit,
        slots: <OsgSlot>[],
        templateCornerRadiusNorm: 1.0,
      );
      expect(pill.templateCornerRadiusPx(100, 100), closeTo(50, 1e-9));
    });
  });

  group("OsgPreset.fromJson migration", () {
    test("schema v1 maps slot box from canvas space into graphic-local", () {
      final OsgPreset p = OsgPreset.fromJson(<String, Object?>{
        "schemaVersion": 1,
        "enabled": true,
        "templateRelativePath": "osg/t.png",
        "frame": <String, Object?>{
          "x": 0.0,
          "y": 0.75,
          "width": 0.5,
          "height": 0.25,
        },
        "slots": <Map<String, Object?>>[
          <String, Object?>{
            "textSource": "fixed",
            "fixedText": "Hi",
            "box": <String, Object?>{
              "x": 0.1,
              "y": 0.8,
              "width": 0.2,
              "height": 0.05,
            },
          },
        ],
      });
      expect(p.slots.single.box.x, closeTo(0.2, 1e-9));
      expect(p.slots.single.box.y, closeTo(0.2, 1e-9));
    });
  });

  group("OsgPreset.requiredSemanticTypeIds", () {
    test("fromJson reads sorted unique ids", () {
      final OsgPreset p = OsgPreset.fromJson(<String, Object?>{
        "schemaVersion": 7,
        "enabled": true,
        "templateRelativePath": "",
        "frame": <String, Object?>{"x": 0, "y": 0, "width": 1, "height": 1},
        "slots": <Map<String, Object?>>[],
        "requiredSemanticTypeIds": <Object?>[3, 1, 3, "2"],
      });
      expect(p.requiredSemanticTypeIds, <int>[1, 2, 3]);
    });

    test("semanticRequirementsSatisfiedBy", () {
      const OsgPreset p = OsgPreset(
        enabled: true,
        templateRelativePath: "",
        frame: OsgNormRect.unit,
        slots: <OsgSlot>[],
        requiredSemanticTypeIds: <int>[1, 2],
      );
      expect(p.semanticRequirementsSatisfiedBy(<int>{1}), isFalse);
      expect(p.semanticRequirementsSatisfiedBy(<int>{1, 2}), isTrue);
    });

    test("osgMissingSemanticRequirementsMessage uses type names", () {
      const OsgPreset p = OsgPreset(
        enabled: true,
        templateRelativePath: "",
        frame: OsgNormRect.unit,
        slots: <OsgSlot>[],
        requiredSemanticTypeIds: <int>[7],
      );
      final String msg = osgMissingSemanticRequirementsMessage(
        preset: p,
        semanticTypeIdsOnMedia: <int>{},
        tagSemanticTypes: const <TagSemanticType>[
          TagSemanticType(id: 7, name: "Guest"),
        ],
      );
      expect(msg, contains("Guest"));
    });
  });
}
