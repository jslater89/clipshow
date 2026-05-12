import "package:obs_clipshow/src/osg/osg_models.dart";

/// Clamps [OsgPreset.frame] so it stays inside the unit canvas with a minimum size.
OsgNormRect osgClampFrame(OsgNormRect f, {double minNorm = 0.05}) {
  double w = f.width.clamp(minNorm, 1.0);
  double h = f.height.clamp(minNorm, 1.0);
  double x = f.x.clamp(0.0, 1.0 - w);
  double y = f.y.clamp(0.0, 1.0 - h);
  w = w.clamp(minNorm, 1.0 - x);
  h = h.clamp(minNorm, 1.0 - y);
  return OsgNormRect(x: x, y: y, width: w, height: h);
}

/// Clamps a text slot box to 0..1 **graphic-local** coordinates.
OsgNormRect osgClampSlotBox(OsgNormRect b, {double minNorm = 0.02}) {
  double w = b.width.clamp(minNorm, 1.0);
  double h = b.height.clamp(minNorm, 1.0);
  double x = b.x.clamp(0.0, 1.0 - w);
  double y = b.y.clamp(0.0, 1.0 - h);
  w = w.clamp(minNorm, 1.0 - x);
  h = h.clamp(minNorm, 1.0 - y);
  return OsgNormRect(x: x, y: y, width: w, height: h);
}

/// Playout [OsgPreset.frame]: width and height stay between [minNormW] / [minNormH] and 1.0
/// in normalized canvas space; x and y may extend up to [maxFractionOffscreen] times size
/// past each edge so roughly half the frame can sit off-screen (for wide or tall templates).
OsgNormRect osgClampFrameForPlayout(
  OsgNormRect f, {
  double minNormW = 0.05,
  double minNormH = 0.05,
  double maxFractionOffscreen = 0.5,
}) {
  double w = f.width.clamp(minNormW, 1.0);
  double h = f.height.clamp(minNormH, 1.0);
  final double minX = -maxFractionOffscreen * w;
  final double maxX = 1.0 - w + maxFractionOffscreen * w;
  final double minY = -maxFractionOffscreen * h;
  final double maxY = 1.0 - h + maxFractionOffscreen * h;
  final double x = f.x.clamp(minX, maxX);
  final double y = f.y.clamp(minY, maxY);
  return OsgNormRect(x: x, y: y, width: w, height: h);
}

/// Locks normalized frame size so on-screen aspect matches template pixels.
/// [playoutAspect] is canvas width ÷ height (logical). [imageWidthOverHeight] is image pixels.
OsgNormRect osgClampFrameWithImageAspect({
  required OsgNormRect frame,
  required double imageWidthOverHeight,
  required double playoutAspect,
  double minNormW = 0.05,
  double minNormH = 0.05,
  double maxFractionOffscreen = 0.5,
}) {
  if (imageWidthOverHeight <= 0 || playoutAspect <= 0) {
    return osgClampFrameForPlayout(
      frame,
      minNormW: minNormW,
      minNormH: minNormH,
      maxFractionOffscreen: maxFractionOffscreen,
    );
  }
  double w = frame.width.clamp(minNormW, 1.0);
  double h = w * playoutAspect / imageWidthOverHeight;
  if (h < minNormH) {
    h = minNormH;
    w = h * imageWidthOverHeight / playoutAspect;
  }
  if (h > 1.0) {
    h = 1.0;
    w = (h * imageWidthOverHeight / playoutAspect).clamp(minNormW, 1.0);
  }
  if (w > 1.0) {
    w = 1.0;
    h = w * playoutAspect / imageWidthOverHeight;
    if (h < minNormH) {
      h = minNormH;
      w = (h * imageWidthOverHeight / playoutAspect).clamp(minNormW, 1.0);
    }
  }
  final double minX = -maxFractionOffscreen * w;
  final double maxX = 1.0 - w + maxFractionOffscreen * w;
  final double minY = -maxFractionOffscreen * h;
  final double maxY = 1.0 - h + maxFractionOffscreen * h;
  final double x = frame.x.clamp(minX, maxX);
  final double y = frame.y.clamp(minY, maxY);
  return OsgNormRect(x: x, y: y, width: w, height: h);
}

/// After a width-only resize from a bottom-right drag, recompute height from aspect.
OsgNormRect osgFrameResizeWidthPreservingAspect({
  required OsgNormRect frame,
  required double newWidth,
  required double imageWidthOverHeight,
  required double playoutAspect,
}) {
  double w = newWidth;
  double h = w * playoutAspect / imageWidthOverHeight;
  return osgClampFrameWithImageAspect(
    frame: OsgNormRect(x: frame.x, y: frame.y, width: w, height: h),
    imageWidthOverHeight: imageWidthOverHeight,
    playoutAspect: playoutAspect,
  );
}
