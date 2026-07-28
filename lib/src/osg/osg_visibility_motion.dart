import "package:flutter/material.dart";

import "package:obs_clipshow/src/osg/osg_models.dart";

/// Sample state for editor motion preview (matches playout easing in [osgVisibilityOpacityAndOffset]).
class OsgMotionPreviewSample {
  const OsgMotionPreviewSample({
    required this.shown,
    required this.isEnterLeg,
  });

  /// 0 = hidden end, 1 = fully visible rest.
  final double shown;

  /// True during the enter half of a preview sequence.
  final bool isEnterLeg;
}

/// Default visibility transition length; matches [OsgPreset.defaultVisibilityTransitionDurationMs].
const Duration osgPresetVisibilityTransitionDuration = Duration(
  milliseconds: OsgPreset.defaultVisibilityTransitionDurationMs,
);

/// Full slide offset at hidden extent for [motion] (rest is [Offset.zero]).
Offset osgVisibilitySlideOffsetForMotion(
  OsgPresetVisibilityMotion motion,
  double distanceNorm,
  double frameWidthPx,
  double frameHeightPx,
) {
  final double m = OsgPreset.clampVisibilitySlideDistanceNorm(distanceNorm);
  switch (motion) {
    case OsgPresetVisibilityMotion.none:
      return Offset.zero;
    case OsgPresetVisibilityMotion.left:
      return Offset(-m * frameWidthPx, 0);
    case OsgPresetVisibilityMotion.right:
      return Offset(m * frameWidthPx, 0);
    case OsgPresetVisibilityMotion.top:
      return Offset(0, -m * frameHeightPx);
    case OsgPresetVisibilityMotion.bottom:
      return Offset(0, m * frameHeightPx);
  }
}

/// Maps controller [shown] (0 = hidden, 1 = rest) to opacity progress when fade
/// may finish earlier than the full transition (both start together).
double osgVisibilityFadeShown({
  required bool entering,
  required double shown,
  required int fadeMs,
  required int transitionMs,
}) {
  final double s = shown.clamp(0.0, 1.0);
  final int transition = OsgPreset.clampVisibilityDurationMs(transitionMs);
  final int fade = fadeMs <= transition ? fadeMs : transition;
  if (transition <= 0 || fade >= transition) {
    return s;
  }
  final double f = fade / transition;
  if (f <= 0) {
    return entering ? 1.0 : 0.0;
  }
  if (entering) {
    return (s / f).clamp(0.0, 1.0);
  }
  return (1.0 - (1.0 - s) / f).clamp(0.0, 1.0);
}

/// [shown] 0 = hidden, 1 = rest. [entering] true while animating on; false while animating off.
///
/// Slide always tracks the full transition. Opacity may complete earlier when
/// [enterFadeDurationMs] / [exitFadeDurationMs] are shorter than the matching
/// transition duration (fade-only motion uses the full duration for opacity).
({double opacity, Offset offset}) osgVisibilityOpacityAndOffset({
  required bool entering,
  required double shown,
  required double layerOpacity,
  required OsgPresetVisibilityMotion enterMotion,
  required double enterSlideDistanceNorm,
  required OsgPresetVisibilityMotion exitMotion,
  required double exitSlideDistanceNorm,
  required double frameWidthPx,
  required double frameHeightPx,
  int enterDurationMs = OsgPreset.defaultVisibilityTransitionDurationMs,
  int exitDurationMs = OsgPreset.defaultVisibilityTransitionDurationMs,
  int enterFadeDurationMs = OsgPreset.defaultVisibilityTransitionDurationMs,
  int exitFadeDurationMs = OsgPreset.defaultVisibilityTransitionDurationMs,
}) {
  final double lo = layerOpacity.clamp(0.0, 1.0);
  final double s = shown.clamp(0.0, 1.0);
  if (entering) {
    final int transitionMs = OsgPreset.clampVisibilityDurationMs(enterDurationMs);
    final int fadeMs = OsgPreset.effectiveVisibilityFadeDurationMs(
      fadeMs: enterFadeDurationMs,
      transitionMs: transitionMs,
      motion: enterMotion,
    );
    final double fadeShown = osgVisibilityFadeShown(
      entering: true,
      shown: s,
      fadeMs: fadeMs,
      transitionMs: transitionMs,
    );
    final double tSlide = Curves.easeOutCubic.transform(s);
    final double tFade = Curves.easeOutCubic.transform(fadeShown);
    final Offset full = osgVisibilitySlideOffsetForMotion(
      enterMotion,
      enterSlideDistanceNorm,
      frameWidthPx,
      frameHeightPx,
    );
    return (opacity: lo * tFade, offset: full * (1.0 - tSlide));
  }
  final int transitionMs = OsgPreset.clampVisibilityDurationMs(exitDurationMs);
  final int fadeMs = OsgPreset.effectiveVisibilityFadeDurationMs(
    fadeMs: exitFadeDurationMs,
    transitionMs: transitionMs,
    motion: exitMotion,
  );
  final double fadeShown = osgVisibilityFadeShown(
    entering: false,
    shown: s,
    fadeMs: fadeMs,
    transitionMs: transitionMs,
  );
  final double tSlide = Curves.easeInCubic.transform(s);
  final double tFade = Curves.easeInCubic.transform(fadeShown);
  final Offset full = osgVisibilitySlideOffsetForMotion(
    exitMotion,
    exitSlideDistanceNorm,
    frameWidthPx,
    frameHeightPx,
  );
  return (opacity: lo * tFade, offset: full * (1.0 - tSlide));
}
