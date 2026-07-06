import "dart:io";
import "dart:typed_data";
import "dart:ui" as ui;

import "package:obs_clipshow/src/osg/osg_mode_key_color.dart";
import "package:obs_clipshow/src/osg/osg_models.dart";
import "package:path/path.dart" as p;

/// Collects RGB samples from enabled OSG presets (solids, text, image templates).
Future<List<OsgRgb>> collectForbiddenOsgRgbColors({
  required OsgWorkspaceConfig config,
  required String workspaceRoot,
}) async {
  final List<OsgRgb> out = <OsgRgb>[];
  final Set<int> seen = <int>{};
  void addRgb(OsgRgb rgb) {
    if (seen.add(rgb.packedRgb)) {
      out.add(rgb);
    }
  }

  for (int i = 0; i < config.workspacePresets.length; i++) {
    final OsgPreset preset = config.workspacePresets[i];
    if (!preset.enabled) {
      continue;
    }
    if (preset.templateBackgroundKind == OsgTemplateBackgroundKind.solid) {
      addRgb(OsgRgb.fromArgb(preset.templateSolidArgb));
    }
    if (preset.templateBackgroundKind == OsgTemplateBackgroundKind.image &&
        _canRenderImageTemplate(preset, workspaceRoot)) {
      final String abs = p.normalize(
        p.join(
          p.absolute(workspaceRoot.trim()),
          preset.templateRelativePath.trim().replaceAll("/", p.separator),
        ),
      );
      for (final OsgRgb rgb in await _sampleImageRgbColors(abs)) {
        addRgb(rgb);
      }
    }
    for (final OsgSlot slot in preset.slots) {
      final int a = (slot.textColorArgb >> 24) & 0xFF;
      if (a >= 128) {
        addRgb(OsgRgb.fromArgb(slot.textColorArgb));
      }
    }
  }
  return out;
}

bool _canRenderImageTemplate(OsgPreset preset, String workspaceRoot) {
  if (workspaceRoot.trim().isEmpty) {
    return false;
  }
  final String rel = preset.templateRelativePath.trim();
  if (rel.isEmpty) {
    return false;
  }
  final String abs = p.normalize(
    p.join(
      p.absolute(workspaceRoot.trim()),
      rel.replaceAll("/", p.separator),
    ),
  );
  return File(abs).existsSync();
}

Future<List<OsgRgb>> _sampleImageRgbColors(String absolutePath) async {
  final File file = File(absolutePath);
  if (!file.existsSync()) {
    return const <OsgRgb>[];
  }
  try {
    final Uint8List bytes = await file.readAsBytes();
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    final ui.Image image = frame.image;
    try {
      final int w = image.width;
      final int h = image.height;
      if (w <= 0 || h <= 0) {
        return const <OsgRgb>[];
      }
      final ByteData? data = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (data == null) {
        return const <OsgRgb>[];
      }
      final List<OsgRgb> out = <OsgRgb>[];
      final Set<int> seen = <int>{};
      const int step = 4;
      for (int y = 0; y < h; y += step) {
        for (int x = 0; x < w; x += step) {
          final int offset = (y * w + x) * 4;
          final int r = data.getUint8(offset);
          final int g = data.getUint8(offset + 1);
          final int b = data.getUint8(offset + 2);
          final int a = data.getUint8(offset + 3);
          if (a < 16) {
            continue;
          }
          final OsgRgb rgb = OsgRgb(r, g, b);
          if (seen.add(rgb.packedRgb)) {
            out.add(rgb);
          }
        }
      }
      return out;
    } finally {
      image.dispose();
    }
  } catch (_) {
    return const <OsgRgb>[];
  }
}

OsgKeyColorAnalysis analyzeOsgKeyColor({
  required int keyColorArgb,
  required Iterable<OsgRgb> forbidden,
}) {
  final int opaqueKey = keyColorArgb | 0xFF000000;
  final List<OsgKeyColorConflict> conflicts = <OsgKeyColorConflict>[];
  final OsgRgb key = OsgRgb.fromArgb(opaqueKey);
  double minDistance = double.infinity;
  for (final OsgRgb sample in forbidden) {
    final double d = osgRgbDistance(key, sample);
    if (d < minDistance) {
      minDistance = d;
    }
    if (d < OsgModeKeyColorSettings.minSafeRgbDistance) {
      conflicts.add(
        OsgKeyColorConflict(
          presetIndex: -1,
          description: "Graphic color #${sample.packedRgb.toRadixString(16).padLeft(6, "0").toUpperCase()}",
          colorArgb: 0xFF000000 | sample.packedRgb,
          distanceRgb: d,
        ),
      );
    }
  }
  conflicts.sort((OsgKeyColorConflict a, OsgKeyColorConflict b) {
    return a.distanceRgb.compareTo(b.distanceRgb);
  });
  if (minDistance.isInfinite) {
    minDistance = double.infinity;
  }
  return OsgKeyColorAnalysis(
    keyColorArgb: opaqueKey,
    minDistanceRgb: minDistance,
    isSafe: osgKeyColorIsSafe(opaqueKey, forbidden),
    recommendedObsSimilarityMax: osgRecommendedObsSimilarityMax(minDistance),
    conflicts: conflicts,
  );
}

Future<OsgKeyColorSuggestion> suggestOsgModeKeyColor({
  required OsgWorkspaceConfig config,
  required String workspaceRoot,
}) async {
  final List<OsgRgb> forbidden = await collectForbiddenOsgRgbColors(
    config: config,
    workspaceRoot: workspaceRoot,
  );
  final List<OsgKeyColorAnalysis> ranked = <OsgKeyColorAnalysis>[];
  for (final int candidate in OsgModeKeyColorSettings.candidateKeyColorsArgb) {
    final OsgKeyColorAnalysis analysis = analyzeOsgKeyColor(
      keyColorArgb: candidate,
      forbidden: forbidden,
    );
    if (analysis.isSafe) {
      ranked.add(analysis);
    }
  }
  ranked.sort((OsgKeyColorAnalysis a, OsgKeyColorAnalysis b) {
    final double da = a.minDistanceRgb.isInfinite ? 9999 : a.minDistanceRgb;
    final double db = b.minDistanceRgb.isInfinite ? 9999 : b.minDistanceRgb;
    return db.compareTo(da);
  });
  final OsgKeyColorAnalysis fallback = analyzeOsgKeyColor(
    keyColorArgb: OsgModeKeyColorSettings.defaultKeyColorArgb,
    forbidden: forbidden,
  );
  final OsgKeyColorAnalysis chosen =
      ranked.isNotEmpty ? ranked.first : fallback;
  return OsgKeyColorSuggestion(
    suggestedKeyColorArgb: chosen.keyColorArgb,
    analysis: chosen,
    alternateCandidates: ranked.length > 1 ? ranked.sublist(1) : const <OsgKeyColorAnalysis>[],
  );
}

Future<OsgKeyColorAnalysis> validateOsgModeKeyColor({
  required int keyColorArgb,
  required OsgWorkspaceConfig config,
  required String workspaceRoot,
}) async {
  final List<OsgRgb> forbidden = await collectForbiddenOsgRgbColors(
    config: config,
    workspaceRoot: workspaceRoot,
  );
  return analyzeOsgKeyColor(keyColorArgb: keyColorArgb, forbidden: forbidden);
}
