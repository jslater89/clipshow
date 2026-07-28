import "dart:async";
import "dart:convert";
import "dart:io";

import "package:flutter/foundation.dart";
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

/// Offline single-item bake: one-pass ffmpeg (seek master + scale/letterbox +
/// overlay) with OSG frames streamed as raw straight RGBA on stdin.
///
/// Frame rendering happens on the root isolate (dart:ui restriction) with
/// periodic event-loop yields and last-frame reuse when visibility is static.
class OsgBakeService {
  OsgBakeService({this.shouldCancel, this.onProgress});

  /// When this returns true, the bake aborts at the next safe checkpoint.
  final bool Function()? shouldCancel;

  /// Called as overlay frames are written to ffmpeg stdin (`framesDone` is
  /// 1…[frameCount]). Suitable for UI progress; may fire every frame.
  final void Function(int framesDone, int frameCount)? onProgress;

  final Logger _logger = Logger("OsgBakeService");

  static const int _yieldEveryNFrames = 5;
  static const int _logProgressEveryPct = 5;

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
    Process? ffmpeg;
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
      final String bakedPath = p.join(tempDir.path, "baked.mp4");
      final int w = request.outputSize.width;
      final int h = request.outputSize.height;
      final int frameCount = (durationMs * fps / 1000).ceil().clamp(1, 1 << 24);
      final int expectedRawBytes = w * h * 4;

      renderer = OsgFrameRenderer(
        presets: request.presets,
        cues: request.recipe.cues,
        clipDurationMs: durationMs,
        outputWidthPx: w,
        outputHeightPx: h,
        semanticTextByTypeId: request.semanticTextByTypeId,
        annotationsText: request.annotationsText,
        workspaceRoot: request.workspaceRoot,
      );
      await renderer.loadAssets();

      final String filter =
          "[0:v]scale=$w:$h:force_original_aspect_ratio=decrease,"
          "pad=$w:$h:(ow-iw)/2:(oh-ih)/2[bg];"
          "[bg][1:v]overlay=0:0,format=yuv420p[v]";
      final List<String> args = <String>[
        "-y",
        "-ss",
        (request.inMs / 1000).toStringAsFixed(3),
        "-t",
        (durationMs / 1000).toStringAsFixed(3),
        "-i",
        request.masterFileAbsolute,
        "-f",
        "rawvideo",
        "-pix_fmt",
        "rgba",
        "-video_size",
        "${w}x$h",
        "-framerate",
        fps.toStringAsFixed(6),
        "-i",
        "pipe:0",
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
        "aac",
        "-b:a",
        "192k",
        "-shortest",
        bakedPath,
      ];

      _logger.info(
        "Bake render+composite: $frameCount frames at "
        "${fps.toStringAsFixed(3)} fps (${w}x$h).",
      );
      _logger.fine("ffmpeg (bake): ${args.join(" ")}");

      final DateTime bakeStart = DateTime.now();
      ffmpeg = await Process.start("ffmpeg", args);
      final StringBuffer stderrBuf = StringBuffer();
      final StreamSubscription<List<int>> stderrSub = ffmpeg.stderr.listen(
        (List<int> chunk) => stderrBuf.write(utf8.decode(chunk, allowMalformed: true)),
      );
      // Drain stdout so a full pipe cannot stall ffmpeg.
      final StreamSubscription<List<int>> stdoutSub =
          ffmpeg.stdout.listen((_) {});

      List<double>? lastFingerprint;
      Uint8List? lastRaw;
      int rasterizedFrames = 0;
      int reusedFrames = 0;
      int lastLoggedPct = -_logProgressEveryPct;

      try {
        for (int i = 0; i < frameCount; i++) {
          if (_cancelled) {
            await _killFfmpeg(ffmpeg);
            return const OsgBakeResult(errorMessage: "Bake cancelled.");
          }
          final int tMs = (i * 1000 / fps).round();
          final List<double> fingerprint =
              renderer.visibilityFingerprintAt(tMs);
          final Uint8List raw;
          if (lastRaw != null &&
              lastFingerprint != null &&
              listEquals(fingerprint, lastFingerprint)) {
            raw = lastRaw;
            reusedFrames++;
          } else {
            raw = await renderer.renderFrameRawRgba(tMs);
            if (raw.length != expectedRawBytes) {
              await _killFfmpeg(ffmpeg);
              return OsgBakeResult(
                errorMessage:
                    "OSG frame byte length mismatch: got ${raw.length}, "
                    "expected $expectedRawBytes.",
              );
            }
            lastRaw = raw;
            lastFingerprint = fingerprint;
            rasterizedFrames++;
          }
          ffmpeg.stdin.add(raw);
          await ffmpeg.stdin.flush();

          final int framesDone = i + 1;
          onProgress?.call(framesDone, frameCount);
          final int pct = ((framesDone * 100) / frameCount).floor();
          if (pct >= lastLoggedPct + _logProgressEveryPct ||
              framesDone == frameCount) {
            lastLoggedPct = pct;
            _logger.info(
              "Bake progress: $pct% ($framesDone/$frameCount)",
            );
          }

          if (i % _yieldEveryNFrames == 0) {
            await Future<void>.delayed(Duration.zero);
          }
        }
        await ffmpeg.stdin.close();
      } catch (e) {
        await _killFfmpeg(ffmpeg);
        rethrow;
      } finally {
        await stderrSub.cancel();
        await stdoutSub.cancel();
      }

      final int exitCode = await ffmpeg.exitCode;
      final Duration streamDuration = DateTime.now().difference(bakeStart);
      if (exitCode != 0) {
        final String stderr = stderrBuf.toString();
        final String tail = stderr.length > 600
            ? stderr.substring(stderr.length - 600)
            : stderr;
        _logger.warning("ffmpeg bake failed ($exitCode): $tail");
        return OsgBakeResult(errorMessage: "ffmpeg bake failed: $tail");
      }

      _logger.info(
        "Bake render+composite complete: $streamDuration "
        "(rasterized $rasterizedFrames, reused $reusedFrames).",
      );

      // Copy into the export folder with a unique name.
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
      if (ffmpeg != null) {
        try {
          ffmpeg.kill();
        } catch (_) {}
      }
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

  Future<void> _killFfmpeg(Process process) async {
    try {
      process.kill();
    } catch (_) {}
    try {
      await process.exitCode;
    } catch (_) {}
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
