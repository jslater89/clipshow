import "dart:ui";

import "package:obs_clipshow/src/osg/osg_bake_models.dart";
import "package:obs_clipshow/src/osg/osg_models.dart";
import "package:obs_clipshow/src/osg/osg_visibility_motion.dart";

/// Resolves [cue] anchors against the actual clip duration, clamped to
/// `0..clipDurationMs`. `endMs <= startMs` means the cue is never visible
/// (silent no-op by design — savvy-operator assumption).
({int startMs, int endMs}) resolveCueWindow(OsgBakeCue cue, int clipDurationMs) {
  int resolve(OsgBakeAnchor a) => switch (a.kind) {
    OsgBakeAnchorKind.clipStart => 0,
    OsgBakeAnchorKind.clipEnd => clipDurationMs,
    OsgBakeAnchorKind.absoluteMs => a.valueMs,
    OsgBakeAnchorKind.offsetFromEndMs => clipDurationMs - a.valueMs,
  };
  final int s = resolve(cue.start).clamp(0, clipDurationMs);
  final int e = resolve(cue.end).clamp(0, clipDurationMs);
  return (startMs: s, endMs: e);
}

/// Samples a cue's visibility at [tMs] relative to its resolved window
/// (`windowStartMs`/`windowEndMs` are the nominal, fully-visible instants).
///
/// Bake semantics: the OSG must be fully visible *at* `windowStartMs` and
/// *at* `windowEndMs`, not merely by the time the window has elapsed. So the
/// enter animation is scheduled to land at full opacity exactly at
/// `windowStartMs` — it starts `enterDurationMs` earlier, at
/// `windowStartMs - enterDurationMs`. When the window starts at (or near) the
/// clip start, that lead-in falls before `t=0` and is never sampled, which is
/// how "skip the intro transition at clip start" falls out naturally. The
/// exit animation begins at `windowEndMs` (still fully visible there) and
/// ramps down to fully hidden by `windowEndMs + exitDurationMs`.
({double opacity, Offset offset}) sampleCueVisibilityAt({
  required OsgPreset preset,
  required int tMs,
  required int windowStartMs,
  required int windowEndMs,
  required double frameWidthPx,
  required double frameHeightPx,
}) {
  if (windowEndMs <= windowStartMs) {
    return (opacity: 0.0, offset: Offset.zero);
  }
  final int enterMs = OsgPreset.clampVisibilityDurationMs(
    preset.visibilityEnterDurationMs,
  );
  final int exitMs = OsgPreset.clampVisibilityDurationMs(
    preset.visibilityExitDurationMs,
  );
  final int activeStartMs = windowStartMs - enterMs;
  final int activeEndMs = windowEndMs + exitMs;
  if (tMs < activeStartMs || tMs >= activeEndMs) {
    return (opacity: 0.0, offset: Offset.zero);
  }
  if (tMs < windowStartMs) {
    final double shown = enterMs <= 0
        ? 1.0
        : ((tMs - activeStartMs) / enterMs).clamp(0.0, 1.0);
    return osgVisibilityOpacityAndOffset(
      entering: true,
      shown: shown,
      layerOpacity: preset.layerOpacity,
      enterMotion: preset.visibilityEnterMotion,
      enterSlideDistanceNorm: preset.visibilityEnterSlideDistanceNorm,
      exitMotion: preset.visibilityExitMotion,
      exitSlideDistanceNorm: preset.visibilityExitSlideDistanceNorm,
      frameWidthPx: frameWidthPx,
      frameHeightPx: frameHeightPx,
    );
  }
  if (tMs < windowEndMs) {
    return osgVisibilityOpacityAndOffset(
      entering: true,
      shown: 1.0,
      layerOpacity: preset.layerOpacity,
      enterMotion: preset.visibilityEnterMotion,
      enterSlideDistanceNorm: preset.visibilityEnterSlideDistanceNorm,
      exitMotion: preset.visibilityExitMotion,
      exitSlideDistanceNorm: preset.visibilityExitSlideDistanceNorm,
      frameWidthPx: frameWidthPx,
      frameHeightPx: frameHeightPx,
    );
  }
  final double shown = exitMs <= 0
      ? 0.0
      : ((activeEndMs - tMs) / exitMs).clamp(0.0, 1.0);
  return osgVisibilityOpacityAndOffset(
    entering: false,
    shown: shown,
    layerOpacity: preset.layerOpacity,
    enterMotion: preset.visibilityEnterMotion,
    enterSlideDistanceNorm: preset.visibilityEnterSlideDistanceNorm,
    exitMotion: preset.visibilityExitMotion,
    exitSlideDistanceNorm: preset.visibilityExitSlideDistanceNorm,
    frameWidthPx: frameWidthPx,
    frameHeightPx: frameHeightPx,
  );
}

/// Samples the visibility of [slot] at [tMs] across all [cues].
///
/// Cues are evaluated in list order; the first cue for [slot] whose active
/// range (window, expanded by the preset's enter/exit lead-in/lead-out) covers
/// [tMs] wins (documented overlap behavior, not an error).
({double opacity, Offset offset}) sampleSlotVisibilityAt({
  required OsgPresetSlot slot,
  required OsgPreset preset,
  required List<OsgBakeCue> cues,
  required int tMs,
  required int clipDurationMs,
  required double frameWidthPx,
  required double frameHeightPx,
}) {
  final int enterMs = OsgPreset.clampVisibilityDurationMs(
    preset.visibilityEnterDurationMs,
  );
  final int exitMs = OsgPreset.clampVisibilityDurationMs(
    preset.visibilityExitDurationMs,
  );
  for (final OsgBakeCue cue in cues) {
    if (cue.slot != slot) {
      continue;
    }
    final ({int startMs, int endMs}) window = resolveCueWindow(
      cue,
      clipDurationMs,
    );
    if (window.endMs <= window.startMs) {
      continue;
    }
    if (tMs < window.startMs - enterMs || tMs >= window.endMs + exitMs) {
      continue;
    }
    return sampleCueVisibilityAt(
      preset: preset,
      tMs: tMs,
      windowStartMs: window.startMs,
      windowEndMs: window.endMs,
      frameWidthPx: frameWidthPx,
      frameHeightPx: frameHeightPx,
    );
  }
  return (opacity: 0.0, offset: Offset.zero);
}
