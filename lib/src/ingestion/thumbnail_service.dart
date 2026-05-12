import "dart:async";
import "dart:collection";
import "dart:io";

import "package:logging/logging.dart";
import "package:path/path.dart" as p;

import "package:obs_clipshow/src/ingestion/media_duration_probe.dart";
import "package:obs_clipshow/src/workspace/workspace_settings.dart";

class _ThumbnailJob {
  const _ThumbnailJob(this.videoPath, this.knownDurationSeconds);

  final String videoPath;

  /// When set (e.g. from ingest-time ffprobe), skips a second ffprobe before ffmpeg.
  final double? knownDurationSeconds;
}

/// Generates JPEG thumbnails next to video files using `ffprobe` + `ffmpeg`.
/// Work runs in the background with bounded concurrency so ingestion stays fast.
/// Default concurrency is [IngestionConcurrencyDefaults.thumbnailDefault] parallel `ffmpeg` processes.
class ThumbnailService {
  ThumbnailService({
    int maxConcurrentJobs = IngestionConcurrencyDefaults.thumbnailDefault,
    this.maxThumbWidth = 960,
    this.maxThumbHeight = 480,
  }) : maxConcurrentJobs = IngestionConcurrencyDefaults.clampThumbnail(
         maxConcurrentJobs,
       );

  static const int defaultMaxThumbWidth = 960;
  static const int defaultMaxThumbHeight = 480;

  int maxConcurrentJobs;
  final int maxThumbWidth;
  final int maxThumbHeight;

  final Logger _logger = Logger("ThumbnailService");
  final StreamController<String> _readyController =
      StreamController<String>.broadcast();

  final Queue<_ThumbnailJob> _queue = Queue<_ThumbnailJob>();
  final Set<String> _queuedOrRunning = <String>{};
  int _activeJobs = 0;
  bool _disposed = false;
  bool _paused = false;

  /// [failureDetail] is null on success (thumbnail present or written).
  void Function(String normalizedPath, String? failureDetail)?
  onThumbnailSettled;

  /// Emits the normalized video path when a thumbnail file has been written.
  Stream<String> get thumbnailReady => _readyController.stream;

  String thumbnailPathForVideo(String videoPath) => "$videoPath.thumb.jpg";

  /// Schedules thumbnail generation without blocking the caller.
  ///
  /// If `*.thumb.jpg` already exists next to the video, returns immediately:
  /// nothing is queued and no [thumbnailReady] event is sent (the list reads
  /// the file directly). This avoids backlog and hundreds of UI rebuilds on startup.
  ///
  /// [knownDurationSeconds] avoids a redundant ffprobe when ingestion already probed duration.
  void requestThumbnail(
    String videoPath, {
    double? knownDurationSeconds,
  }) {
    if (_disposed) {
      return;
    }
    final String normalized = p.normalize(p.absolute(videoPath));
    if (_queuedOrRunning.contains(normalized)) {
      return;
    }

    try {
      final int length = File(normalized).lengthSync();
      if (length == 0) {
        return;
      }
    } on FileSystemException {
      return;
    }

    final String thumbPath = thumbnailPathForVideo(normalized);
    try {
      if (File(thumbPath).existsSync()) {
        onThumbnailSettled?.call(normalized, null);
        return;
      }
    } on FileSystemException {
      // Fall through and queue — generation path will handle missing IO.
    }

    _queuedOrRunning.add(normalized);
    _queue.addLast(
      _ThumbnailJob(normalized, knownDurationSeconds),
    );
    _pumpQueue();
  }

  void setScanPaused(bool paused) {
    _paused = paused;
    if (!paused) {
      _pumpQueue();
    }
  }

  void setMaxConcurrentJobs(int value) {
    maxConcurrentJobs = IngestionConcurrencyDefaults.clampThumbnail(value);
    if (!_disposed && !_paused) {
      _pumpQueue();
    }
  }

  void _pumpQueue() {
    while (!_disposed && !_paused && _activeJobs < maxConcurrentJobs && _queue.isNotEmpty) {
      final _ThumbnailJob job = _queue.removeFirst();
      _activeJobs++;
      unawaited(_generateThumbnailJob(job));
    }
  }

  Future<void> _generateThumbnailJob(_ThumbnailJob job) async {
    try {
      await _generateThumbnail(job);
    } finally {
      _activeJobs--;
      _queuedOrRunning.remove(job.videoPath);
      if (!_disposed) {
        _pumpQueue();
      }
    }
  }

  Future<void> _generateThumbnail(_ThumbnailJob job) async {
    final String videoPath = job.videoPath;
    final File source = File(videoPath);
    if (!await source.exists()) {
      return;
    }
    if (await source.length() == 0) {
      return;
    }

    final String thumbnailPath = thumbnailPathForVideo(videoPath);
    final File thumbnailFile = File(thumbnailPath);
    if (await thumbnailFile.exists()) {
      onThumbnailSettled?.call(videoPath, null);
      if (!_disposed && !_readyController.isClosed) {
        _readyController.add(videoPath);
      }
      return;
    }

    final double? known = job.knownDurationSeconds;
    late final MediaDurationProbeResult probe;
    if (known != null && known > 1e-6) {
      probe = MediaDurationProbeResult.ok(known);
    } else {
      probe = await MediaDurationProbe.probeSeconds(videoPath);
      if (!probe.ok) {
        onThumbnailSettled?.call(videoPath, probe.stderr);
        return;
      }
    }
    final double seekSeconds = probe.durationSeconds == null
        ? 0
        : probe.durationSeconds! * 0.2;

    try {
      final ProcessResult result = await Process.run("ffmpeg", <String>[
        "-y",
        "-ss",
        seekSeconds.toStringAsFixed(3),
        "-i",
        videoPath,
        "-frames:v",
        "1",
        "-vf",
        "scale=$maxThumbWidth:$maxThumbHeight:force_original_aspect_ratio=decrease",
        "-q:v",
        "2",
        thumbnailPath,
      ]);
      if (result.exitCode != 0) {
        onThumbnailSettled?.call(videoPath, "${result.stderr}");
      } else {
        onThumbnailSettled?.call(videoPath, null);
        final int remaining = _queuedOrRunning.length - 1;
        _logger.fine(
          "Generated thumbnail: $thumbnailPath ($remaining remaining)",
        );
        if (!_disposed && !_readyController.isClosed) {
          _readyController.add(videoPath);
        }
      }
    } catch (error) {
      onThumbnailSettled?.call(videoPath, "$error");
    }
  }

  Future<void> deleteThumbnailForVideoPath(String videoPath) async {
    final File thumbnail = File(thumbnailPathForVideo(videoPath));
    if (!await thumbnail.exists()) {
      return;
    }
    await thumbnail.delete();
  }

  Future<void> dispose() async {
    _disposed = true;
    onThumbnailSettled = null;
    _queue.clear();
    _queuedOrRunning.clear();
    await _readyController.close();
  }
}
