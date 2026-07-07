import "dart:io";
import "dart:typed_data";

import "package:obs_clipshow/src/ingestion/media_duration_probe.dart";
import "package:obs_clipshow/src/osg/osg_bake_models.dart";
import "package:obs_clipshow/src/osg/osg_frame_renderer.dart";
import "package:obs_clipshow/src/osg/osg_graphic_export_models.dart";
import "package:obs_clipshow/src/osg/osg_graphic_export_zip.dart";
import "package:obs_clipshow/src/osg/osg_models.dart";

/// Outcome of [OsgGraphicExportService.buildZip].
class OsgGraphicExportResult {
  const OsgGraphicExportResult({
    this.zipBytes,
    this.errorMessage,
    this.suggestedFileName = "",
  });

  final Uint8List? zipBytes;
  final String? errorMessage;
  final String suggestedFileName;
}

/// Everything needed to export hold-state OSG graphics for a bake recipe.
class OsgGraphicExportRequest {
  const OsgGraphicExportRequest({
    required this.masterFileAbsolute,
    required this.inMs,
    required this.outMs,
    required this.recipe,
    required this.presets,
    required this.outputSize,
    required this.semanticTextByTypeId,
    required this.annotationsText,
    required this.workspaceRoot,
    required this.sourceClipDisplayName,
    required this.sourceClipFileName,
    required this.sourceClipWorkspaceRelativePath,
    required this.exportBaseName,
  });

  final String masterFileAbsolute;
  final int inMs;

  /// Null = play to end of file (bare master or open-ended clip).
  final int? outMs;

  final OsgBakeRecipe recipe;
  final List<OsgPreset> presets;
  final PlayoutOutputSize outputSize;
  final Map<int, String> semanticTextByTypeId;
  final String annotationsText;
  final String workspaceRoot;
  final String sourceClipDisplayName;
  final String sourceClipFileName;
  final String sourceClipWorkspaceRelativePath;
  final String exportBaseName;
}

/// Renders hold-state OSG PNGs and bundles them with a manifest ZIP.
class OsgGraphicExportService {
  Future<OsgGraphicExportResult> buildZip(OsgGraphicExportRequest request) async {
    if (!request.outputSize.isValid) {
      return const OsgGraphicExportResult(
        errorMessage: "Invalid playout canvas size for OSG export.",
      );
    }
    if (request.recipe.cues.isEmpty) {
      return const OsgGraphicExportResult(
        errorMessage: "Bake recipe has no OSG cues to export.",
      );
    }
    final File master = File(request.masterFileAbsolute);
    if (!await master.exists()) {
      return OsgGraphicExportResult(
        errorMessage: "Source file missing: ${request.masterFileAbsolute}",
      );
    }

    int? outMs = request.outMs;
    if (outMs == null) {
      final MediaDurationProbeResult probe =
          await MediaDurationProbe.probeSeconds(request.masterFileAbsolute);
      final int? probedMs = probe.durationMs;
      if (!probe.ok || probedMs == null || probedMs <= 0) {
        return const OsgGraphicExportResult(
          errorMessage: "Could not determine source duration for OSG export.",
        );
      }
      outMs = probedMs;
    }
    final int clipDurationMs = outMs - request.inMs;
    if (clipDurationMs <= 0) {
      return const OsgGraphicExportResult(
        errorMessage: "Clip range is empty; nothing to export.",
      );
    }

    final Set<OsgPresetSlot> slots =
        request.recipe.cues.map((OsgBakeCue c) => c.slot).toSet();
    OsgFrameRenderer? renderer;
    try {
      renderer = OsgFrameRenderer(
        presets: request.presets,
        cues: const <OsgBakeCue>[],
        clipDurationMs: clipDurationMs,
        outputWidthPx: request.outputSize.width,
        outputHeightPx: request.outputSize.height,
        semanticTextByTypeId: request.semanticTextByTypeId,
        annotationsText: request.annotationsText,
        workspaceRoot: request.workspaceRoot,
      );
      await renderer.loadAssetsForSlots(slots);

      final Map<OsgPresetSlot, Uint8List> pngBySlot =
          <OsgPresetSlot, Uint8List>{};
      for (final OsgPresetSlot slot in slots) {
        pngBySlot[slot] = await renderer.renderSlotHoldStatePng(slot);
      }

      final Map<String, Object?> manifest = buildOsgGraphicExportManifest(
        recipe: request.recipe,
        canvas: request.outputSize,
        sourceClipDisplayName: request.sourceClipDisplayName,
        sourceClipFileName: request.sourceClipFileName,
        sourceClipWorkspaceRelativePath: request.sourceClipWorkspaceRelativePath,
        inMs: request.inMs,
        outMs: outMs,
        clipDurationMs: clipDurationMs,
        presets: request.presets,
        semanticTextByTypeId: request.semanticTextByTypeId,
        annotationsText: request.annotationsText,
      );

      final Uint8List zipBytes = buildOsgGraphicExportZip(
        manifest: manifest,
        pngBySlot: pngBySlot,
      );

      return OsgGraphicExportResult(
        zipBytes: zipBytes,
        suggestedFileName: osgGraphicExportSuggestedZipFileName(
          clipBaseName: request.exportBaseName,
          recipeName: request.recipe.name,
        ),
      );
    } catch (e) {
      return OsgGraphicExportResult(errorMessage: "OSG export failed: $e");
    } finally {
      renderer?.dispose();
    }
  }
}
