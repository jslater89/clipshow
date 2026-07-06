import "dart:io";

/// Reads the first video stream's frame rate via `ffprobe` (`r_frame_rate`,
/// e.g. "30000/1001"). Used to pick the bake export FPS.
class MediaFrameRateProbe {
  MediaFrameRateProbe._();

  static const double fallbackFps = 30;

  /// Returns the probed FPS, or [fallbackFps] when ffprobe fails or the
  /// output cannot be parsed.
  static Future<double> probeFps(String videoPath) async {
    try {
      final ProcessResult result = await Process.run("ffprobe", <String>[
        "-v",
        "error",
        "-select_streams",
        "v:0",
        "-show_entries",
        "stream=r_frame_rate",
        "-of",
        "default=noprint_wrappers=1:nokey=1",
        videoPath,
      ]);
      if (result.exitCode != 0) {
        return fallbackFps;
      }
      final String out = (result.stdout as String).trim();
      final double? fps = _parseRational(out);
      if (fps == null || fps <= 0 || !fps.isFinite) {
        return fallbackFps;
      }
      // Guard against absurd probe results (corrupt headers).
      if (fps < 1 || fps > 240) {
        return fallbackFps;
      }
      return fps;
    } catch (_) {
      return fallbackFps;
    }
  }

  static double? _parseRational(String raw) {
    final String s = raw.trim();
    if (s.isEmpty) {
      return null;
    }
    final int slash = s.indexOf("/");
    if (slash < 0) {
      return double.tryParse(s);
    }
    final double? num = double.tryParse(s.substring(0, slash));
    final double? den = double.tryParse(s.substring(slash + 1));
    if (num == null || den == null || den == 0) {
      return null;
    }
    return num / den;
  }
}
