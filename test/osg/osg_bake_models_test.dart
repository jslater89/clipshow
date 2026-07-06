import "package:flutter_test/flutter_test.dart";

import "package:obs_clipshow/src/osg/osg_bake_models.dart";
import "package:obs_clipshow/src/osg/osg_models.dart";

void main() {
  group("OsgBakeRecipe JSON round-trip", () {
    test("encodes and decodes a recipe list preserving all fields", () {
      final List<OsgBakeRecipe> recipes = <OsgBakeRecipe>[
        const OsgBakeRecipe(
          id: 1,
          name: "Drone Lower Third",
          cues: <OsgBakeCue>[
            OsgBakeCue(
              slot: OsgPresetSlot.preset1,
              start: OsgBakeAnchor.clipStart(),
              end: OsgBakeAnchor.absoluteMs(4000),
            ),
            OsgBakeCue(
              slot: OsgPresetSlot.preset2,
              start: OsgBakeAnchor.clipStart(),
              end: OsgBakeAnchor.clipEnd(),
            ),
            OsgBakeCue(
              slot: OsgPresetSlot.preset4,
              start: OsgBakeAnchor.offsetFromEndMs(4000),
              end: OsgBakeAnchor.clipEnd(),
            ),
          ],
        ),
        const OsgBakeRecipe(
          id: 2,
          name: "Mid Clip Bug",
          cues: <OsgBakeCue>[
            OsgBakeCue(
              slot: OsgPresetSlot.preset3,
              start: OsgBakeAnchor.absoluteMs(2000),
              end: OsgBakeAnchor.absoluteMs(10000),
            ),
          ],
        ),
      ];

      final String encoded = encodeOsgBakeRecipesToStorageJson(recipes);
      final List<OsgBakeRecipe> decoded =
          decodeOsgBakeRecipesFromStorageJson(encoded);

      expect(decoded.length, 2);
      expect(decoded[0].id, 1);
      expect(decoded[0].name, "Drone Lower Third");
      expect(decoded[0].cues.length, 3);
      expect(decoded[0].cues[0].slot, OsgPresetSlot.preset1);
      expect(decoded[0].cues[0].start.kind, OsgBakeAnchorKind.clipStart);
      expect(decoded[0].cues[0].end.kind, OsgBakeAnchorKind.absoluteMs);
      expect(decoded[0].cues[0].end.valueMs, 4000);
      expect(decoded[0].cues[1].end.kind, OsgBakeAnchorKind.clipEnd);
      expect(decoded[0].cues[2].start.kind, OsgBakeAnchorKind.offsetFromEndMs);
      expect(decoded[0].cues[2].start.valueMs, 4000);
      expect(decoded[1].id, 2);
      expect(decoded[1].cues.single.slot, OsgPresetSlot.preset3);
      expect(decoded[1].cues.single.start.valueMs, 2000);
      expect(decoded[1].cues.single.end.valueMs, 10000);
    });

    test("decode returns empty list for null, empty, and invalid JSON", () {
      expect(decodeOsgBakeRecipesFromStorageJson(null), isEmpty);
      expect(decodeOsgBakeRecipesFromStorageJson(""), isEmpty);
      expect(decodeOsgBakeRecipesFromStorageJson("not json"), isEmpty);
      expect(decodeOsgBakeRecipesFromStorageJson("{}"), isEmpty);
    });

    test("unknown anchor kind and slot fall back to safe defaults", () {
      const String raw =
          '[{"schemaVersion":1,"id":7,"name":"X","cues":'
          '[{"slot":"presetNope","start":{"kind":"mystery","valueMs":5},'
          '"end":{"kind":"clipEnd","valueMs":0}}]}]';
      final List<OsgBakeRecipe> decoded =
          decodeOsgBakeRecipesFromStorageJson(raw);
      expect(decoded.single.cues.single.slot, OsgPresetSlot.preset1);
      expect(
        decoded.single.cues.single.start.kind,
        OsgBakeAnchorKind.clipStart,
      );
    });

    test("negative valueMs clamps to zero on decode", () {
      const String raw =
          '[{"schemaVersion":1,"id":1,"name":"N","cues":'
          '[{"slot":"preset1","start":{"kind":"absoluteMs","valueMs":-100},'
          '"end":{"kind":"clipEnd","valueMs":0}}]}]';
      final List<OsgBakeRecipe> decoded =
          decodeOsgBakeRecipesFromStorageJson(raw);
      expect(decoded.single.cues.single.start.valueMs, 0);
    });
  });

  group("Bake label helpers", () {
    test("anchor labels", () {
      expect(
        osgBakeAnchorLabel(const OsgBakeAnchor.clipStart()),
        "Clip Start",
      );
      expect(osgBakeAnchorLabel(const OsgBakeAnchor.clipEnd()), "Clip End");
      expect(osgBakeAnchorLabel(const OsgBakeAnchor.absoluteMs(4000)), "4s");
      expect(
        osgBakeAnchorLabel(const OsgBakeAnchor.absoluteMs(2500)),
        "2.5s",
      );
      expect(
        osgBakeAnchorLabel(const OsgBakeAnchor.offsetFromEndMs(4000)),
        "End \u2212 4s",
      );
    });

    test("cue summary label", () {
      const OsgBakeCue cue = OsgBakeCue(
        slot: OsgPresetSlot.preset1,
        start: OsgBakeAnchor.clipStart(),
        end: OsgBakeAnchor.absoluteMs(4000),
      );
      expect(osgBakeCueSummaryLabel(cue), "OSG 6: Clip Start \u2192 4s");
    });
  });
}
