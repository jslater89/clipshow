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

/// [shown] 0 = hidden, 1 = rest. [entering] true while animating on; false while animating off.
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
}) {
  final double lo = layerOpacity.clamp(0.0, 1.0);
  final double s = shown.clamp(0.0, 1.0);
  if (entering) {
    final double t = Curves.easeOutCubic.transform(s);
    final Offset full = osgVisibilitySlideOffsetForMotion(
      enterMotion,
      enterSlideDistanceNorm,
      frameWidthPx,
      frameHeightPx,
    );
    return (opacity: lo * t, offset: full * (1.0 - t));
  }
  final double t = Curves.easeInCubic.transform(s);
  final Offset full = osgVisibilitySlideOffsetForMotion(
    exitMotion,
    exitSlideDistanceNorm,
    frameWidthPx,
    frameHeightPx,
  );
  return (opacity: lo * t, offset: full * (1.0 - t));
}
