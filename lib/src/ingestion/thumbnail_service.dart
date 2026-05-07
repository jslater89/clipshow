import "dart:io";

import "package:logging/logging.dart";

class ThumbnailService {
  ThumbnailService();

  final Logger _logger = Logger("ThumbnailService");

  String thumbnailPathForVideo(String videoPath) => "$videoPath.thumb.jpg";

  Future<void> generateThumbnail(String videoPath) async {
    final File source = File(videoPath);
    if (!await source.exists()) {
      return;
    }

    final String thumbnailPath = thumbnailPathForVideo(videoPath);
    final File thumbnailFile = File(thumbnailPath);
    if (await thumbnailFile.exists()) {
      _logger.finer("Thumbnail already exists, skipping: $thumbnailPath");
      return;
    }
    final double? durationSeconds = await _probeDurationSeconds(videoPath);
    final double seekSeconds = durationSeconds == null ? 0 : durationSeconds * 0.2;

    try {
      final ProcessResult result = await Process.run(
        "ffmpeg",
        <String>[
          "-y",
          "-ss",
          seekSeconds.toStringAsFixed(3),
          "-i",
          videoPath,
          "-frames:v",
          "1",
          "-q:v",
          "2",
          thumbnailPath,
        ],
      );
      if (result.exitCode != 0) {
        _logger.warning(
          "ffmpeg failed for thumbnail generation ($videoPath): ${result.stderr}",
        );
      } else {
        _logger.fine("Generated thumbnail: $thumbnailPath");
      }
    } catch (error) {
      _logger.warning("Unable to run ffmpeg for thumbnail generation: $error");
    }
  }

  Future<void> deleteThumbnailForVideoPath(String videoPath) async {
    final File thumbnail = File(thumbnailPathForVideo(videoPath));
    if (!await thumbnail.exists()) {
      return;
    }
    await thumbnail.delete();
    _logger.fine("Deleted thumbnail: ${thumbnail.path}");
  }

  Future<double?> _probeDurationSeconds(String videoPath) async {
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
      if (result.exitCode != 0) {
        _logger.finer("ffprobe failed for $videoPath: ${result.stderr}");
        return null;
      }
      return double.tryParse((result.stdout as String).trim());
    } catch (error) {
      _logger.finer("Unable to run ffprobe: $error");
      return null;
    }
  }
}
