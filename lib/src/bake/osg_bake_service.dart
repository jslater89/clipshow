import "dart:async";
import "dart:io";
import "dart:typed_data";

import "package:logging/logging.dart";
import "package:path/path.dart" as p;

import "package:obs_clipshow/src/ingestion/media_duration_probe.dart";
import "package:obs_clipshow/src/ingestion/media_frame_rate_probe.dart";
import "package:obs_clipshow/src/osg/osg_bake_models.dart";
import "package:obs_clipshow/src/osg/osg_frame_renderer.dart";
import "package:obs_clipshow/src/osg/osg_models.dart";

/// Outcome of a single bake export ([destPath] xor [errorMessage]).
class OsgBakeResult {
  const OsgBakeResult({this.destPath, this.errorMessage});

  final String? destPath;
  final String? errorMessage;
}

/// Everything needed to bake one item; caller resolves media paths, clip
/// range, semantic text, and output directory beforehand.
class OsgBakeRequest {
  const OsgBakeRequest({
    required this.masterFileAbsolute,
    required this.inMs,
    required this.outMs,
    required this.recipe,
    required this.presets,
    required this.outputSize,
    required this.semanticTextByTypeId,
    required this.annotationsText,
    required this.workspaceRoot,
    required this.outputDirAbsolute,
    required this.exportBaseName,
  });

  final String masterFileAbsolute;
  final int inMs;

  /// Null = play to end of file (bare master or open-ended clip).
  final int? outMs;

  final OsgBakeRecipe recipe;

  /// Five presets in [OsgPresetSlot] order.
  final List<OsgPreset> presets;

  final PlayoutOutputSize outputSize;
  final Map<int, String> semanticTextByTypeId;
  final String annotationsText;
  final String workspaceRoot;
  final String outputDirAbsolute;

  /// Preferred output filename stem (UI display name or source basename).
  final String exportBaseName;
}

/// Offline single-item bake: ffmpeg trim, OSG PNG frame sequence render,
/// ffmpeg scale/letterbox + overlay composite, copy into the export folder.
///
/// Frame rendering happens on the root isolate (dart:ui restriction) with
/// periodic event-loop yields; ffmpeg passes run as external processes.
class OsgBakeService {
  OsgBakeService({this.shouldCancel});

  /// When this returns true, the bake aborts at the next safe checkpoint.
  final bool Function()? shouldCancel;

  final Logger _logger = Logger("OsgBakeService");

  static const int _yieldEveryNFrames = 5;

  bool get _cancelled => shouldCancel?.call() ?? false;

  Future<OsgBakeResult> bake(OsgBakeRequest request) async {
    if (!request.outputSize.isValid) {
      return const OsgBakeResult(
        errorMessage: "Invalid playout canvas size for bake.",
      );
    }
    final File master = File(request.masterFileAbsolute);
    if (!await master.exists()) {
      return OsgBakeResult(
        errorMessage: "Source file missing: ${request.masterFileAbsolute}",
      );
    }

    Directory? tempDir;
    OsgFrameRenderer? renderer;
    try {
      // Resolve the effective clip range in ms.
      int? outMs = request.outMs;
      if (outMs == null) {
        final MediaDurationProbeResult probe =
            await MediaDurationProbe.probeSeconds(request.masterFileAbsolute);
        final int? probedMs = probe.durationMs;
        if (!probe.ok || probedMs == null || probedMs <= 0) {
          return const OsgBakeResult(
            errorMessage: "Could not determine source duration for bake.",
          );
        }
        outMs = probedMs;
      }
      final int durationMs = outMs - request.inMs;
      if (durationMs <= 0) {
        return const OsgBakeResult(
          errorMessage: "Clip range is empty; nothing to bake.",
        );
      }

      final double fps = await MediaFrameRateProbe.probeFps(
        request.masterFileAbsolute,
      );

      tempDir = await Directory.systemTemp.createTemp("obs_clipshow_bake_");
      final String trimmedPath = p.join(tempDir.path, "trimmed.mp4");
      final Directory framesDir = Directory(p.join(tempDir.path, "frames"));
      await framesDir.create();

      final DateTime trimStart = DateTime.now();
      // 1) Trim (re-encode for frame-accurate in/out; scaling happens in the
      // composite pass so there is a single scale+pad).
      final String? trimError = await _runFfmpeg(<String>[
        "-y",
        "-ss",
        (request.inMs / 1000).toStringAsFixed(3),
        "-i",
        request.masterFileAbsolute,
        "-t",
        (durationMs / 1000).toStringAsFixed(3),
        "-c:v",
        "libx264",
        "-preset",
        "veryfast",
        "-crf",
        "18",
        "-c:a",
        "aac",
        "-b:a",
        "192k",
        trimmedPath,
      ], phase: "trim");
      if (trimError != null) {
        return OsgBakeResult(errorMessage: trimError);
      }
      if (_cancelled) {
        return const OsgBakeResult(errorMessage: "Bake cancelled.");
      }
      final Duration trimDuration = DateTime.now().difference(trimStart);
      _logger.info("Trim complete: $trimDuration");

      // 2) Render the OSG overlay PNG sequence at canvas resolution.
      final DateTime renderStart = DateTime.now();
      renderer = OsgFrameRenderer(
        presets: request.presets,
        cues: request.recipe.cues,
        clipDurationMs: durationMs,
        outputWidthPx: request.outputSize.width,
        outputHeightPx: request.outputSize.height,
        semanticTextByTypeId: request.semanticTextByTypeId,
        annotationsText: request.annotationsText,
        workspaceRoot: request.workspaceRoot,
      );
      await renderer.loadAssets();
      final int frameCount = (durationMs * fps / 1000).ceil().clamp(1, 1 << 24);
      _logger.info(
        "Bake render: $frameCount frames at ${fps.toStringAsFixed(3)} fps "
        "(${request.outputSize.width}x${request.outputSize.height}).",
      );

      for (int i = 0; i < frameCount; i++) {
        if (_cancelled) {
          return const OsgBakeResult(errorMessage: "Bake cancelled.");
        }
        final int tMs = (i * 1000 / fps).round();
        final Uint8List png = await renderer.renderFramePng(tMs);
        final String framePath = p.join(
          framesDir.path,
          "frame_${i.toString().padLeft(6, "0")}.png",
        );
        await File(framePath).writeAsBytes(png, flush: false);
        if (i % _yieldEveryNFrames == 0) {
          await Future<void>.delayed(Duration.zero);
        }
        //_logger.finest("rendered frame $i/$frameCount");
      }

      final Duration renderDuration = DateTime.now().difference(renderStart);
      _logger.info("Render OSG frames complete: $renderDuration");

      if (_cancelled) {
        return const OsgBakeResult(errorMessage: "Bake cancelled.");
      }

      final DateTime compositeStart = DateTime.now();
      // 3) Composite: scale/letterbox source into the canvas, overlay OSG.
      final int w = request.outputSize.width;
      final int h = request.outputSize.height;
      final String bakedPath = p.join(tempDir.path, "baked.mp4");
      final String filter =
          "[0:v]scale=$w:$h:force_original_aspect_ratio=decrease,"
          "pad=$w:$h:(ow-iw)/2:(oh-ih)/2[bg];"
          "[bg][1:v]overlay=0:0,format=yuv420p[v]";
      final String? compositeError = await _runFfmpeg(<String>[
        "-y",
        "-i",
        trimmedPath,
        "-framerate",
        fps.toStringAsFixed(6),
        "-i",
        p.join(framesDir.path, "frame_%06d.png"),
        "-filter_complex",
        filter,
        "-map",
        "[v]",
        "-map",
        "0:a?",
        "-c:v",
        "libx264",
        "-preset",
        "veryfast",
        "-crf",
        "18",
        "-c:a",
        "copy",
        "-shortest",
        bakedPath,
      ], phase: "composite");
      if (compositeError != null) {
        return OsgBakeResult(errorMessage: compositeError);
      }
      final Duration compositeDuration = DateTime.now().difference(compositeStart);
      _logger.info("Composite complete: $compositeDuration");

      final Duration bakeDuration = DateTime.now().difference(trimStart);
      _logger.info("Bake complete: $bakeDuration");

      // 4) Copy into the export folder with a unique name.
      final String dest = await _copyToOutputDir(
        sourceAbsolute: bakedPath,
        outputDirAbsolute: request.outputDirAbsolute,
        baseName:
            "${_sanitizeExportBaseName(request.exportBaseName)}_baked.mp4",
      );
      _logger.info("Bake complete: $dest");
      return OsgBakeResult(destPath: dest);
    } catch (e, st) {
      _logger.warning("Bake failed: $e\n$st");
      return OsgBakeResult(errorMessage: "Bake failed: $e");
    } finally {
      renderer?.dispose();
      if (tempDir != null) {
        try {
          await tempDir.delete(recursive: true);
        } catch (e) {
          _logger.warning("Could not delete bake temp dir ${tempDir.path}: $e");
        }
      }
    }
  }

  Future<String?> _runFfmpeg(
    List<String> args, {
    required String phase,
  }) async {
    _logger.fine("ffmpeg ($phase): ${args.join(" ")}");
    final ProcessResult result = await Process.run("ffmpeg", args);
    if (result.exitCode != 0) {
      final String stderr = "${result.stderr}";
      final String tail = stderr.length > 600
          ? stderr.substring(stderr.length - 600)
          : stderr;
      _logger.warning("ffmpeg $phase failed (${result.exitCode}): $tail");
      return "ffmpeg $phase failed: $tail";
    }
    return null;
  }

  static String _sanitizeExportBaseName(String raw) {
    String name = p.basenameWithoutExtension(raw.trim());
    name = name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), "_").trim();
    return name.isEmpty ? "baked" : name;
  }

  Future<String> _copyToOutputDir({
    required String sourceAbsolute,
    required String outputDirAbsolute,
    required String baseName,
  }) async {
    await Directory(outputDirAbsolute).create(recursive: true);
    String dest = p.normalize(p.join(outputDirAbsolute, baseName));
    int i = 1;
    while (await File(dest).exists()) {
      final String name = p.basenameWithoutExtension(baseName);
      final String ext = p.extension(baseName);
      dest = p.normalize(p.join(outputDirAbsolute, "${name}_$i$ext"));
      i++;
    }
    await File(sourceAbsolute).copy(dest);
    return dest;
  }
}
