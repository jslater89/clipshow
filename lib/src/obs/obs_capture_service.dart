import "dart:async";
import "dart:io";

import "package:logging/logging.dart";
import "package:obs_websocket/event.dart";
import "package:obs_websocket/obs_websocket.dart";
import "package:path/path.dart" as p;

import "package:obs_clipshow/src/obs/capture_path_utils.dart";
import "package:obs_clipshow/src/workspace/workspace_settings.dart";

final Logger _captureCopyLogger = Logger("ObsCaptureCopy");

/// OBS may return from [ObsWebSocket.record.stopRecord] before the container is
/// fully flushed. Wait until [absolutePath] exists, has non-zero size, and the
/// size is unchanged for several consecutive polls.
Future<void> waitForRecordingFileReady(
  String absolutePath, {
  Duration pollInterval = const Duration(milliseconds: 150),
  Duration timeout = const Duration(seconds: 120),
}) async {
  final File file = File(absolutePath);
  final DateTime deadline = DateTime.now().add(timeout);
  int? lastNonZeroSize;
  int stablePolls = 0;
  const int requiredStablePolls = 4;

  while (DateTime.now().isBefore(deadline)) {
    if (!await file.exists()) {
      await Future<void>.delayed(pollInterval);
      continue;
    }
    final int size = (await file.stat()).size;
    if (size == 0) {
      stablePolls = 0;
      lastNonZeroSize = null;
      await Future<void>.delayed(pollInterval);
      continue;
    }
    if (lastNonZeroSize != null && size == lastNonZeroSize) {
      stablePolls++;
      if (stablePolls >= requiredStablePolls) {
        _captureCopyLogger.fine(
          "Staging file stable at $size bytes: $absolutePath",
        );
        return;
      }
    } else {
      stablePolls = 1;
      lastNonZeroSize = size;
      _captureCopyLogger.fine("Staging file size $size bytes (waiting for stable): $absolutePath");
    }
    await Future<void>.delayed(pollInterval);
  }
  throw TimeoutException(
    "Recording did not finish writing within ${timeout.inSeconds}s: $absolutePath",
  );
}

/// Drive OBS recording directory + start/stop for Capture Mode (single session).
class ObsCaptureService {
  ObsCaptureService({required this.url, this.password});

  final String url;
  final String? password;
  final Logger _logger = Logger("ObsCaptureService");

  ObsWebSocket? _client;
  String? _previousRecordDirectory;

  /// Whether OBS is currently writing a record output.
  Future<bool> isObsRecordActive() async {
    final ObsWebSocket client = await _ensureClient();
    final RecordStatusResponse status = await client.record.getRecordStatus();
    return status.outputActive;
  }

  /// Record playout program output without changing the current program scene.
  Future<void> startPlayoutRecording({required String stagingAbsolute}) async {
    final ObsWebSocket client = await _ensureClient();
    if (await isObsRecordActive()) {
      throw StateError("OBS is already recording.");
    }
    final RecordDirectoryResponse prev = await client.config
        .getRecordDirectory();
    _previousRecordDirectory = prev.recordDirectory;
    await Directory(stagingAbsolute).create(recursive: true);
    _logger.info("OBS SetRecordDirectory (playout) -> $stagingAbsolute");
    await client.config.setRecordDirectory(stagingAbsolute);
    await client.record.startRecord();
    _logger.info("OBS StartRecord issued (playout).");
  }

  Future<void> startRecording({
    required String workspaceAbsolute,
    required CapturePathsSettings paths,
    required String? captureSceneName,
  }) async {
    final ObsWebSocket client = await _ensureClient();
    final RecordDirectoryResponse prev = await client.config
        .getRecordDirectory();
    _previousRecordDirectory = prev.recordDirectory;
    final String recordingAbs = CapturePathUtils.normalizedRecordingDir(
      workspaceAbsolute: workspaceAbsolute,
      settings: paths,
    );
    await Directory(recordingAbs).create(recursive: true);
    _logger.info("OBS SetRecordDirectory -> $recordingAbs");
    await client.config.setRecordDirectory(recordingAbs);
    final String? scene = captureSceneName?.trim();
    if (scene != null && scene.isNotEmpty) {
      _logger.info("OBS SetCurrentProgramScene -> $scene");
      await client.scenes.setCurrentProgramScene(scene);
    }
    await client.record.startRecord();
    _logger.info("OBS StartRecord issued.");
  }

  Future<String?> stopRecordingStagingPath({
    Duration waitForEvent = const Duration(seconds: 5),
  }) async {
    final ObsWebSocket client = await _ensureClient();
    String? fromStop;
    try {
      final String raw = await client.record.stopRecord();
      final String trimmed = raw.trim();
      if (trimmed.isNotEmpty) {
        fromStop = p.normalize(trimmed);
      }
    } catch (e, st) {
      _logger.warning("StopRecord failed or returned empty: $e\n$st");
    }
    if (fromStop != null) {
      return fromStop;
    }
    try {
      final RecordStateChanged ev = await client
          .waitForTypedEvent<RecordStateChanged>(
            eventType: "RecordStateChanged",
            predicate: (RecordStateChanged e) =>
                e.outputPath.trim().isNotEmpty && !e.outputActive,
            timeout: waitForEvent,
          );
      final String path = ev.outputPath.trim();
      if (path.isNotEmpty) {
        return p.normalize(path);
      }
    } catch (e, st) {
      _logger.warning("RecordStateChanged fallback failed: $e\n$st");
    }
    return null;
  }

  Future<void> restoreObsRecordDirectoryAndClose() async {
    final ObsWebSocket? client = _client;
    if (client != null) {
      final String? prev = _previousRecordDirectory;
      if (prev != null && prev.isNotEmpty) {
        try {
          await client.config.setRecordDirectory(prev);
          _logger.info("OBS record directory restored.");
        } catch (e, st) {
          _logger.warning("Failed to restore OBS record directory: $e\n$st");
        }
      }
      await client.close();
    }
    _client = null;
    _previousRecordDirectory = null;
  }

  Future<ObsWebSocket> _ensureClient() async {
    if (_client != null) {
      return _client!;
    }
    _logger.info("Connecting to OBS at $url");
    _client = await ObsWebSocket.connect(url, password: password);
    return _client!;
  }
}

/// Copies a finished recording into [outputDirAbsolute], then removes the staging file.
Future<String> copyCaptureToOutputDir({
  required String stagingFileAbsolute,
  required String outputDirAbsolute,
}) async {
  final String normalizedStaging = p.normalize(stagingFileAbsolute);
  await waitForRecordingFileReady(normalizedStaging);

  final Directory dir = Directory(outputDirAbsolute);
  await dir.create(recursive: true);
  final String base = p.basename(normalizedStaging);
  String dest = p.normalize(p.join(outputDirAbsolute, base));
  final File src = File(normalizedStaging);
  if (!await src.exists()) {
    throw StateError("Staging file missing: $normalizedStaging");
  }
  int i = 1;
  while (await File(dest).exists()) {
    final String name = p.basenameWithoutExtension(base);
    final String ext = p.extension(base);
    dest = p.normalize(p.join(outputDirAbsolute, "${name}_$i$ext"));
    i++;
  }
  await src.copy(dest);
  final int outBytes = (await File(dest).stat()).size;
  _captureCopyLogger.fine("Copied capture to $dest ($outBytes bytes)");
  if (dest != normalizedStaging) {
    try {
      await src.delete();
      _captureCopyLogger.fine("Removed staging file $normalizedStaging");
    } catch (e, st) {
      _captureCopyLogger.warning(
        "Copied to $dest but could not remove staging file: $e\n$st",
      );
    }
  }
  return dest;
}
