import "dart:convert";

import "package:obs_clipshow/src/osg/osg_bake_cue_resolver.dart";
import "package:obs_clipshow/src/osg/osg_bake_models.dart";
import "package:obs_clipshow/src/osg/osg_models.dart";

/// Serialized OSG graphic export manifest schema version.
const int osgGraphicExportSchemaVersion = 2;

/// Manifest entry name inside the export ZIP.
const String osgGraphicExportManifestEntry = "manifest.json";

/// Root manifest key for a preset slot (e.g. `osg6` for hotkey 6).
String osgGraphicExportSlotKey(OsgPresetSlot slot) =>
    "osg${slot.playoutHotkeyDigitLabel}";

/// PNG filename for a preset slot inside the export ZIP.
String osgGraphicExportPngFileName(OsgPresetSlot slot) =>
    "${osgGraphicExportSlotKey(slot)}.png";

Map<String, int> osgGraphicExportFrameCanvasPx({
  required OsgNormRect frameNorm,
  required PlayoutOutputSize canvas,
}) {
  return <String, int>{
    "x": (frameNorm.x * canvas.width).round(),
    "y": (frameNorm.y * canvas.height).round(),
    "width": (frameNorm.width * canvas.width).round(),
    "height": (frameNorm.height * canvas.height).round(),
  };
}

/// Full hidden slide distance along the motion axis (pixels), matching bake/playout.
int osgGraphicExportSlideDistanceCanvasPx({
  required OsgPresetVisibilityMotion motion,
  required double slideDistanceNorm,
  required double frameWidthPx,
  required double frameHeightPx,
}) {
  final double distance = OsgPreset.clampVisibilitySlideDistanceNorm(
    slideDistanceNorm,
  );
  return switch (motion) {
    OsgPresetVisibilityMotion.none => 0,
    OsgPresetVisibilityMotion.left ||
    OsgPresetVisibilityMotion.right => (distance * frameWidthPx).round(),
    OsgPresetVisibilityMotion.top ||
    OsgPresetVisibilityMotion.bottom => (distance * frameHeightPx).round(),
  };
}

Map<String, Object?> osgGraphicExportMotionBlock({
  required OsgPresetVisibilityMotion motion,
  required double slideDistanceNorm,
  required double frameWidthPx,
  required double frameHeightPx,
  required int durationMs,
  required int fadeDurationMs,
  required String easing,
}) {
  final int transitionMs = OsgPreset.clampVisibilityDurationMs(durationMs);
  final int fadeMs = OsgPreset.effectiveVisibilityFadeDurationMs(
    fadeMs: fadeDurationMs,
    transitionMs: transitionMs,
    motion: motion,
  );
  return <String, Object?>{
    "motion": motion.name,
    "slideDistanceNorm": OsgPreset.clampVisibilitySlideDistanceNorm(
      slideDistanceNorm,
    ),
    "slideDistanceCanvasPx": osgGraphicExportSlideDistanceCanvasPx(
      motion: motion,
      slideDistanceNorm: slideDistanceNorm,
      frameWidthPx: frameWidthPx,
      frameHeightPx: frameHeightPx,
    ),
    "durationMs": transitionMs,
    "fadeDurationMs": fadeMs,
    "easing": easing,
  };
}

Map<String, Object?> osgGraphicExportCueTimingBlock({
  required OsgBakeCue cue,
  required OsgPreset preset,
  required int clipDurationMs,
}) {
  final ({int startMs, int endMs}) window = resolveCueWindow(
    cue,
    clipDurationMs,
  );
  final int enterMs = OsgPreset.clampVisibilityDurationMs(
    preset.visibilityEnterDurationMs,
  );
  final int exitMs = OsgPreset.clampVisibilityDurationMs(
    preset.visibilityExitDurationMs,
  );
  final bool valid = window.endMs > window.startMs;
  final Map<String, Object?> block = <String, Object?>{
    "in": cue.start.toJson(),
    "out": cue.end.toJson(),
    "valid": valid,
  };
  if (!valid) {
    return block;
  }
  block["inResolvedMs"] = window.startMs;
  block["outResolvedMs"] = window.endMs;
  block["enterAnimationStartMs"] = window.startMs - enterMs;
  block["exitAnimationEndMs"] = window.endMs + exitMs;
  return block;
}

Map<String, Object?> osgGraphicExportSlotManifest({
  required OsgPresetSlot slot,
  required OsgPreset preset,
  required PlayoutOutputSize canvas,
  required List<OsgBakeCue> slotCues,
  required int clipDurationMs,
  required Map<int, String> semanticTextByTypeId,
  required String annotationsText,
}) {
  final Map<String, int> frameCanvasPx = osgGraphicExportFrameCanvasPx(
    frameNorm: preset.frame,
    canvas: canvas,
  );
  final double frameWidthPx = frameCanvasPx["width"]!.toDouble();
  final double frameHeightPx = frameCanvasPx["height"]!.toDouble();

  final Map<String, String> resolvedBySemanticTypeId = <String, String>{};
  for (final OsgSlot textSlot in preset.slots) {
    if (textSlot.textSource != OsgTextSource.semantic ||
        textSlot.semanticTypeId == null) {
      continue;
    }
    final int id = textSlot.semanticTypeId!;
    resolvedBySemanticTypeId["$id"] = semanticTextByTypeId[id] ?? "";
  }

  return <String, Object?>{
    "slot": slot.name,
    "file": osgGraphicExportPngFileName(slot),
    "frameNorm": preset.frame.toJson(),
    "frameCanvasPx": frameCanvasPx,
    "layerOpacity": preset.layerOpacity,
    "enter": osgGraphicExportMotionBlock(
      motion: preset.visibilityEnterMotion,
      slideDistanceNorm: preset.visibilityEnterSlideDistanceNorm,
      frameWidthPx: frameWidthPx,
      frameHeightPx: frameHeightPx,
      durationMs: preset.visibilityEnterDurationMs,
      fadeDurationMs: preset.visibilityEnterFadeDurationMs,
      easing: "easeOutCubic",
    ),
    "exit": osgGraphicExportMotionBlock(
      motion: preset.visibilityExitMotion,
      slideDistanceNorm: preset.visibilityExitSlideDistanceNorm,
      frameWidthPx: frameWidthPx,
      frameHeightPx: frameHeightPx,
      durationMs: preset.visibilityExitDurationMs,
      fadeDurationMs: preset.visibilityExitFadeDurationMs,
      easing: "easeInCubic",
    ),
    "cues": slotCues
        .map(
          (OsgBakeCue cue) => osgGraphicExportCueTimingBlock(
            cue: cue,
            preset: preset,
            clipDurationMs: clipDurationMs,
          ),
        )
        .toList(),
    "text": <String, Object?>{
      "resolvedBySemanticTypeId": resolvedBySemanticTypeId,
      "annotations": annotationsText,
    },
  };
}

Map<String, Object?> buildOsgGraphicExportManifest({
  required OsgBakeRecipe recipe,
  required PlayoutOutputSize canvas,
  required String sourceClipDisplayName,
  required String sourceClipFileName,
  required String sourceClipWorkspaceRelativePath,
  required int inMs,
  required int? outMs,
  required int clipDurationMs,
  required List<OsgPreset> presets,
  required Map<int, String> semanticTextByTypeId,
  required String annotationsText,
}) {
  final Map<String, Object?> manifest = <String, Object?>{
    "schemaVersion": osgGraphicExportSchemaVersion,
    "recipe": <String, Object?>{"id": recipe.id, "name": recipe.name},
    "canvas": <String, int>{"width": canvas.width, "height": canvas.height},
    "sourceClip": <String, Object?>{
      "displayName": sourceClipDisplayName,
      "fileName": sourceClipFileName,
      "workspaceRelativePath": sourceClipWorkspaceRelativePath,
      "inMs": inMs,
      "outMs": outMs,
      "durationMs": clipDurationMs,
    },
  };

  final Set<OsgPresetSlot> slots =
      recipe.cues.map((OsgBakeCue c) => c.slot).toSet();
  for (final OsgPresetSlot slot in slots) {
    final int index = slot.presetIndex;
    if (index < 0 || index >= presets.length) {
      continue;
    }
    final List<OsgBakeCue> slotCues = recipe.cues
        .where((OsgBakeCue c) => c.slot == slot)
        .toList();
    manifest[osgGraphicExportSlotKey(slot)] = osgGraphicExportSlotManifest(
      slot: slot,
      preset: presets[index],
      canvas: canvas,
      slotCues: slotCues,
      clipDurationMs: clipDurationMs,
      semanticTextByTypeId: semanticTextByTypeId,
      annotationsText: annotationsText,
    );
  }

  return manifest;
}

String encodeOsgGraphicExportManifest(Map<String, Object?> manifest) {
  return const JsonEncoder.withIndent("  ").convert(manifest);
}

String sanitizeOsgGraphicExportBaseName(String raw) {
  String name = raw.trim();
  name = name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), "_").trim();
  return name.isEmpty ? "export" : name;
}

String osgGraphicExportSuggestedZipFileName({
  required String clipBaseName,
  required String recipeName,
}) {
  final String stamp = DateTime.now().toUtc().toIso8601String().replaceAll(
    RegExp(r"[:.-]"),
    "",
  );
  final String clip = sanitizeOsgGraphicExportBaseName(clipBaseName);
  final String recipe = sanitizeOsgGraphicExportBaseName(recipeName);
  return "${clip}_${recipe}_osg_$stamp.zip";
}
