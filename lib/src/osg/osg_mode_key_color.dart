import "dart:math" as math;

import "package:obs_clipshow/src/osg/osg_models.dart";

/// Workspace key fill for OSG Mode window capture (OBS Color Key).
class OsgModeKeyColorSettings {
  const OsgModeKeyColorSettings({required this.keyColorArgb});

  /// Broadcast-style green; opaque ARGB.
  static const int defaultKeyColorArgb = 0xFF00B140;

  static const OsgModeKeyColorSettings defaults = OsgModeKeyColorSettings(
    keyColorArgb: defaultKeyColorArgb,
  );

  final int keyColorArgb;

  /// Minimum Euclidean RGB distance from the key to any OSG graphic color.
  static const double minSafeRgbDistance = 48;

  /// Candidate keys tried by [OsgKeyColorSuggester], best match first.
  static const List<int> candidateKeyColorsArgb = <int>[
    0xFF00B140,
    0xFF00FF00,
    0xFF0000FF,
    0xFFFF00FF,
    0xFF00FFFF,
  ];
}

/// RGB triplet for distance checks (alpha ignored).
class OsgRgb {
  const OsgRgb(this.r, this.g, this.b);

  final int r;
  final int g;
  final int b;

  static OsgRgb fromArgb(int argb) {
    return OsgRgb(
      (argb >> 16) & 0xFF,
      (argb >> 8) & 0xFF,
      argb & 0xFF,
    );
  }

  int get packedRgb => (r << 16) | (g << 8) | b;
}

double osgRgbDistance(OsgRgb a, OsgRgb b) {
  final double dr = (a.r - b.r).toDouble();
  final double dg = (a.g - b.g).toDouble();
  final double db = (a.b - b.b).toDouble();
  return math.sqrt(dr * dr + dg * dg + db * db);
}

double osgKeyColorMinDistance(int keyColorArgb, Iterable<OsgRgb> forbidden) {
  final OsgRgb key = OsgRgb.fromArgb(keyColorArgb);
  double min = double.infinity;
  for (final OsgRgb sample in forbidden) {
    final double d = osgRgbDistance(key, sample);
    if (d < min) {
      min = d;
    }
  }
  if (min.isInfinite) {
    return double.infinity;
  }
  return min;
}

bool osgKeyColorIsSafe(int keyColorArgb, Iterable<OsgRgb> forbidden) {
  if (forbidden.isEmpty) {
    return true;
  }
  return osgKeyColorMinDistance(keyColorArgb, forbidden) >=
      OsgModeKeyColorSettings.minSafeRgbDistance;
}

/// Suggested OBS Color Key similarity ceiling (1–1000) from clearance.
int osgRecommendedObsSimilarityMax(double minDistanceRgb) {
  if (minDistanceRgb.isInfinite) {
    return 500;
  }
  final double normalized = (minDistanceRgb / 441.0).clamp(0.0, 1.0);
  return (normalized * 400 + 80).round().clamp(80, 480);
}

/// A graphic color that is too close to the configured key.
class OsgKeyColorConflict {
  const OsgKeyColorConflict({
    required this.presetIndex,
    required this.description,
    required this.colorArgb,
    required this.distanceRgb,
  });

  final int presetIndex;
  final String description;
  final int colorArgb;
  final double distanceRgb;
}

class OsgKeyColorAnalysis {
  const OsgKeyColorAnalysis({
    required this.keyColorArgb,
    required this.minDistanceRgb,
    required this.isSafe,
    required this.recommendedObsSimilarityMax,
    required this.conflicts,
  });

  final int keyColorArgb;
  final double minDistanceRgb;
  final bool isSafe;
  final int recommendedObsSimilarityMax;
  final List<OsgKeyColorConflict> conflicts;
}

class OsgKeyColorSuggestion {
  const OsgKeyColorSuggestion({
    required this.suggestedKeyColorArgb,
    required this.analysis,
    required this.alternateCandidates,
  });

  final int suggestedKeyColorArgb;
  final OsgKeyColorAnalysis analysis;

  /// Other safe candidates sorted by descending clearance.
  final List<OsgKeyColorAnalysis> alternateCandidates;
}

/// Whether [preset] settings are likely to show green-tinted fringing in OBS
/// Color Key during OSG Mode (partial opacity or fade transitions).
bool osgPresetHasColorKeyUnfriendlyTransparency(OsgPreset preset) {
  if (preset.layerOpacity < 1.0) {
    return true;
  }
  if (preset.visibilityEnterDurationMs > 0 ||
      preset.visibilityExitDurationMs > 0) {
    return true;
  }
  return false;
}
