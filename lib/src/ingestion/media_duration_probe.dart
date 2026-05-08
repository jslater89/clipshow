import "dart:io";

/// Reads container duration via `ffprobe` (`format=duration`), same as thumbnail generation.
class MediaDurationProbeResult {
  const MediaDurationProbeResult._({
    required this.ok,
    this.durationSeconds,
    this.stderr = "",
  });

  final bool ok;
  final double? durationSeconds;
  final String stderr;

  factory MediaDurationProbeResult.ok(double durationSeconds) =>
      MediaDurationProbeResult._(ok: true, durationSeconds: durationSeconds);

  factory MediaDurationProbeResult.fail(String stderr) =>
      MediaDurationProbeResult._(ok: false, stderr: stderr);

  /// Whole milliseconds, suitable for storing next to clip [in_ms] / [out_ms].
  int? get durationMs => durationSeconds == null
      ? null
      : (durationSeconds! * 1000).round();
}

class MediaDurationProbe {
  MediaDurationProbe._();

  static Future<MediaDurationProbeResult> probeSeconds(String videoPath) async {
    try {
      final ProcessResult result = await Process.run(
        "ffprobe",
        <String>[
          "-v",
          "error",
          "-show_entries",
          "format=duration",
          "-of",
          "default=noprint_wrappers=1:nokey=1",
          videoPath,
        ],
      );
      final String stderr = "${result.stderr}";
      if (result.exitCode != 0) {
        return MediaDurationProbeResult.fail(stderr);
      }
      final String out = (result.stdout as String).trim();
      if (out.isEmpty) {
        return MediaDurationProbeResult.fail("empty duration output");
      }
      final double? duration = double.tryParse(out);
      if (duration == null) {
        return MediaDurationProbeResult.fail("unparsed duration: $out");
      }
      return MediaDurationProbeResult.ok(duration);
    } catch (error) {
      return MediaDurationProbeResult.fail("$error");
    }
  }
}
