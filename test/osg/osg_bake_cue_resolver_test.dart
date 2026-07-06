import "package:flutter_test/flutter_test.dart";

import "package:obs_clipshow/src/osg/osg_bake_cue_resolver.dart";
import "package:obs_clipshow/src/osg/osg_bake_models.dart";
import "package:obs_clipshow/src/osg/osg_models.dart";

OsgPreset _preset({
  int enterDurationMs = 240,
  int exitDurationMs = 240,
  OsgPresetVisibilityMotion enterMotion = OsgPresetVisibilityMotion.none,
  OsgPresetVisibilityMotion exitMotion = OsgPresetVisibilityMotion.none,
  double layerOpacity = 1.0,
}) {
  return OsgPreset.empty().copyWith(
    enabled: true,
    visibilityEnterDurationMs: enterDurationMs,
    visibilityExitDurationMs: exitDurationMs,
    visibilityEnterMotion: enterMotion,
    visibilityExitMotion: exitMotion,
    layerOpacity: layerOpacity,
  );
}

void main() {
  group("resolveCueWindow", () {
    const int durationMs = 20000;

    test("clipStart to absoluteMs", () {
      const OsgBakeCue cue = OsgBakeCue(
        slot: OsgPresetSlot.preset1,
        start: OsgBakeAnchor.clipStart(),
        end: OsgBakeAnchor.absoluteMs(4000),
      );
      final ({int startMs, int endMs}) w = resolveCueWindow(cue, durationMs);
      expect(w.startMs, 0);
      expect(w.endMs, 4000);
    });

    test("clipStart to clipEnd covers full clip", () {
      const OsgBakeCue cue = OsgBakeCue(
        slot: OsgPresetSlot.preset2,
        start: OsgBakeAnchor.clipStart(),
        end: OsgBakeAnchor.clipEnd(),
      );
      final ({int startMs, int endMs}) w = resolveCueWindow(cue, durationMs);
      expect(w.startMs, 0);
      expect(w.endMs, durationMs);
    });

    test("offsetFromEndMs start resolves relative to duration", () {
      const OsgBakeCue cue = OsgBakeCue(
        slot: OsgPresetSlot.preset4,
        start: OsgBakeAnchor.offsetFromEndMs(4000),
        end: OsgBakeAnchor.clipEnd(),
      );
      final ({int startMs, int endMs}) w = resolveCueWindow(cue, durationMs);
      expect(w.startMs, 16000);
      expect(w.endMs, durationMs);
    });

    test("window longer than clip clamps to clip bounds", () {
      const OsgBakeCue cue = OsgBakeCue(
        slot: OsgPresetSlot.preset1,
        start: OsgBakeAnchor.clipStart(),
        end: OsgBakeAnchor.absoluteMs(4000),
      );
      final ({int startMs, int endMs}) w = resolveCueWindow(cue, 2000);
      expect(w.startMs, 0);
      expect(w.endMs, 2000);
    });

    test("offsetFromEnd larger than duration clamps to zero", () {
      const OsgBakeCue cue = OsgBakeCue(
        slot: OsgPresetSlot.preset1,
        start: OsgBakeAnchor.offsetFromEndMs(30000),
        end: OsgBakeAnchor.clipEnd(),
      );
      final ({int startMs, int endMs}) w = resolveCueWindow(cue, durationMs);
      expect(w.startMs, 0);
      expect(w.endMs, durationMs);
    });

    test("inverted window resolves without error (never visible)", () {
      const OsgBakeCue cue = OsgBakeCue(
        slot: OsgPresetSlot.preset1,
        start: OsgBakeAnchor.absoluteMs(10000),
        end: OsgBakeAnchor.absoluteMs(2000),
      );
      final ({int startMs, int endMs}) w = resolveCueWindow(cue, durationMs);
      expect(w.endMs <= w.startMs, isTrue);
    });
  });

  group("sampleCueVisibilityAt", () {
    test("hidden well before the enter lead-in and well after the exit tail", () {
      final OsgPreset preset = _preset();
      ({double opacity, Offset offset}) sample(int tMs) =>
          sampleCueVisibilityAt(
            preset: preset,
            tMs: tMs,
            windowStartMs: 1000,
            windowEndMs: 5000,
            frameWidthPx: 1920,
            frameHeightPx: 270,
          );
      expect(sample(0).opacity, 0);
      // Well past windowEndMs + exitDurationMs (5240).
      expect(sample(6000).opacity, 0);
    });

    test(
      "enter ramp lands at full opacity exactly at the window start",
      () {
        final OsgPreset preset = _preset(enterDurationMs: 240);
        ({double opacity, Offset offset}) sample(int tMs) =>
            sampleCueVisibilityAt(
              preset: preset,
              tMs: tMs,
              windowStartMs: 1000,
              windowEndMs: 5000,
              frameWidthPx: 1920,
              frameHeightPx: 270,
            );
        // Enter lead-in starts at windowStartMs - enterDurationMs = 760.
        expect(sample(760).opacity, 0);
        final double mid = sample(880).opacity;
        expect(mid, greaterThan(0));
        expect(mid, lessThan(1));
        // Fully visible exactly at (and past) the window start.
        expect(sample(1000).opacity, 1);
        expect(sample(4999).opacity, 1);
      },
    );

    test(
      "exit ramp begins at the window end and reaches zero after the exit duration",
      () {
        final OsgPreset preset = _preset(exitDurationMs: 240);
        ({double opacity, Offset offset}) sample(int tMs) =>
            sampleCueVisibilityAt(
              preset: preset,
              tMs: tMs,
              windowStartMs: 1000,
              windowEndMs: 5000,
              frameWidthPx: 1920,
              frameHeightPx: 270,
            );
        // Still fully visible at the exact end instant.
        expect(sample(5000).opacity, 1);
        final double mid = sample(5120).opacity;
        expect(mid, greaterThan(0));
        expect(mid, lessThan(1));
        // Fully hidden once the exit duration has elapsed.
        expect(sample(5240).opacity, 0);
      },
    );

    test(
      "intro transition is skipped when the window starts at clip start",
      () {
        final OsgPreset preset = _preset(enterDurationMs: 240);
        // windowStartMs = 0 means the whole lead-in falls before t=0, which
        // is never sampled in practice (bake frames start at t=0).
        final ({double opacity, Offset offset}) atZero = sampleCueVisibilityAt(
          preset: preset,
          tMs: 0,
          windowStartMs: 0,
          windowEndMs: 5000,
          frameWidthPx: 1920,
          frameHeightPx: 270,
        );
        expect(atZero.opacity, 1);
      },
    );

    test("slide offset decays to zero as the enter completes", () {
      final OsgPreset preset = _preset(
        enterDurationMs: 240,
        enterMotion: OsgPresetVisibilityMotion.bottom,
      );
      ({double opacity, Offset offset}) sample(int tMs) =>
          sampleCueVisibilityAt(
            preset: preset,
            tMs: tMs,
            windowStartMs: 1000,
            windowEndMs: 5000,
            frameWidthPx: 1920,
            frameHeightPx: 270,
          );
      expect(sample(760).offset.dy, greaterThan(0));
      expect(sample(1000).offset, Offset.zero);
    });

    test("slide offset grows as the exit progresses", () {
      final OsgPreset preset = _preset(
        exitDurationMs: 240,
        exitMotion: OsgPresetVisibilityMotion.bottom,
      );
      ({double opacity, Offset offset}) sample(int tMs) =>
          sampleCueVisibilityAt(
            preset: preset,
            tMs: tMs,
            windowStartMs: 1000,
            windowEndMs: 5000,
            frameWidthPx: 1920,
            frameHeightPx: 270,
          );
      expect(sample(5000).offset, Offset.zero);
      expect(sample(5239).offset.dy, greaterThan(0));
    });

    test("layer opacity scales the sampled opacity", () {
      final OsgPreset preset = _preset(layerOpacity: 0.5);
      final ({double opacity, Offset offset}) rest = sampleCueVisibilityAt(
        preset: preset,
        tMs: 3000,
        windowStartMs: 0,
        windowEndMs: 5000,
        frameWidthPx: 1920,
        frameHeightPx: 270,
      );
      expect(rest.opacity, closeTo(0.5, 1e-9));
    });
  });

  group("sampleSlotVisibilityAt", () {
    test("only cues for the requested slot apply", () {
      final OsgPreset preset = _preset();
      const List<OsgBakeCue> cues = <OsgBakeCue>[
        OsgBakeCue(
          slot: OsgPresetSlot.preset2,
          start: OsgBakeAnchor.clipStart(),
          end: OsgBakeAnchor.clipEnd(),
        ),
      ];
      final ({double opacity, Offset offset}) forOtherSlot =
          sampleSlotVisibilityAt(
            slot: OsgPresetSlot.preset1,
            preset: preset,
            cues: cues,
            tMs: 1000,
            clipDurationMs: 10000,
            frameWidthPx: 1920,
            frameHeightPx: 270,
          );
      expect(forOtherSlot.opacity, 0);
    });

    test("first matching cue wins for overlapping windows", () {
      final OsgPreset preset = _preset(enterDurationMs: 240);
      const List<OsgBakeCue> cues = <OsgBakeCue>[
        // Starts at 0: fully entered by t=2000.
        OsgBakeCue(
          slot: OsgPresetSlot.preset1,
          start: OsgBakeAnchor.clipStart(),
          end: OsgBakeAnchor.absoluteMs(4000),
        ),
        // Starts at 2000: would still be mid-enter at t=2100.
        OsgBakeCue(
          slot: OsgPresetSlot.preset1,
          start: OsgBakeAnchor.absoluteMs(2000),
          end: OsgBakeAnchor.absoluteMs(8000),
        ),
      ];
      final ({double opacity, Offset offset}) at2100 = sampleSlotVisibilityAt(
        slot: OsgPresetSlot.preset1,
        preset: preset,
        cues: cues,
        tMs: 2100,
        clipDurationMs: 10000,
        frameWidthPx: 1920,
        frameHeightPx: 270,
      );
      // First cue's window contains 2100 and it is fully entered there.
      expect(at2100.opacity, 1);
    });

    test("zero-length window is a silent no-op", () {
      final OsgPreset preset = _preset();
      const List<OsgBakeCue> cues = <OsgBakeCue>[
        OsgBakeCue(
          slot: OsgPresetSlot.preset1,
          start: OsgBakeAnchor.absoluteMs(3000),
          end: OsgBakeAnchor.absoluteMs(3000),
        ),
      ];
      final ({double opacity, Offset offset}) sample = sampleSlotVisibilityAt(
        slot: OsgPresetSlot.preset1,
        preset: preset,
        cues: cues,
        tMs: 3000,
        clipDurationMs: 10000,
        frameWidthPx: 1920,
        frameHeightPx: 270,
      );
      expect(sample.opacity, 0);
    });
  });
}
