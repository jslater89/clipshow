import "dart:async";
import "dart:io";

import "package:logging/logging.dart";
import "package:path/path.dart" as p;
import "package:watcher/watcher.dart";

import 'package:obs_clipshow/src/data/media_repository.dart';
import 'package:obs_clipshow/src/media/master_media_file.dart';
import 'package:obs_clipshow/src/ingestion/media_duration_probe.dart';
import 'package:obs_clipshow/src/ingestion/thumbnail_service.dart';
import 'package:obs_clipshow/src/ingestion/workspace_watcher.dart';
import 'package:obs_clipshow/src/workspace/workspace_media_paths.dart';
import 'package:obs_clipshow/src/workspace/workspace_settings.dart';

/// Stat + optional duration from a single file walk, before DB upsert.
class _MasterFileGatherResult {
  const _MasterFileGatherResult({
    required this.absolutePath,
    required this.storedPath,
    required this.stat,
    this.durationMs,
    this.knownDurationSecondsForThumbnail,
  });

  final String absolutePath;
  final String storedPath;
  final FileStat stat;
  final int? durationMs;

  /// Passed to [ThumbnailService] to skip a redundant ffprobe after ingest probe.
  final double? knownDurationSecondsForThumbnail;
}

class IngestionService {
  IngestionService({
    required WorkspaceWatcher workspaceWatcher,
    ThumbnailService? thumbnailService,
  }) : _workspaceWatcher = workspaceWatcher,
       _thumbnailService = thumbnailService ??
           ThumbnailService(
             maxConcurrentJobs: IngestionConcurrencyDefaults.thumbnailDefault,
           );

  static const Set<String> supportedVideoExtensions = <String>{
    ".mp4",
    ".mov",
    ".mkv",
    ".avi",
    ".webm",
  };

  final WorkspaceWatcher _workspaceWatcher;
  final ThumbnailService _thumbnailService;
  final Logger _logger = Logger("IngestionService");
  final StreamController<List<MasterMediaFile>> _mediaController =
      StreamController<List<MasterMediaFile>>.broadcast();

  StreamSubscription<WatchEvent>? _watchSubscription;
  MediaRepository? _repository;
  String? _workspacePath;
  bool _disposed = false;
  bool _playoutActive = false;
  bool _previewPlaying = false;
  int _scanGeneration = 0;
  Timer? _snapshotDebounce;
  Set<String> _ignoredRelativeFolders = <String>{};
  final Map<String, MasterMediaFile> _snapshotByPath =
      <String, MasterMediaFile>{};

  /// Coalesces rapid MODIFY events (e.g. large file copy) into one upsert after
  /// quiet. Keyed by normalized absolute path.
  final Map<String, Timer> _modifyDebounceTimers = <String, Timer>{};
  final Map<String, String> _modifyDebounceAbsolutePaths = <String, String>{};

  /// Quiet window after the last MODIFY before upsert/ffprobe/UI refresh.
  static const Duration _modifyDebounceWindow = Duration(milliseconds: 2000);

  /// While the post-start directory walk runs, thumbnail settlement can clear
  /// many identical-looking DB rows; defer stream updates until the walk ends.
  bool _initialDirectoryScanActive = false;
  bool _snapshotNotifyDeferredUntilScanIdle = false;

  Stream<List<MasterMediaFile>> get mediaFiles => _mediaController.stream;

  /// Fires when a thumbnail file has been written for a video path (for UI refresh).
  Stream<String> get thumbnailReady => _thumbnailService.thumbnailReady;

  /// Updates parallel ffprobe batch size and thumbnail queue depth (e.g. from workspace settings).
  void applyIngestionConcurrency({
    required int probeConcurrency,
    required int thumbnailConcurrency,
  }) {
    _scanProbeConcurrency =
        IngestionConcurrencyDefaults.clampProbe(probeConcurrency);
    _thumbnailService.setMaxConcurrentJobs(thumbnailConcurrency);
  }

  Future<void> start({
    required String workspacePath,
    required MediaRepository repository,
  }) async {
    _logger.info("Starting ingestion for workspace: $workspacePath");
    _cancelAllModifyDebounces();
    _repository = repository;
    _workspacePath = workspacePath;
    await _refreshIgnoredFolders();
    await _loadSnapshotFromRepository();
    _scanGeneration++;
    _thumbnailService.onThumbnailSettled = _onThumbnailSettled;

    await _watchSubscription?.cancel();
    _workspaceWatcher.start(workspacePath);
    _watchSubscription = _workspaceWatcher.events.listen(_handleWatchEvent);
    _logger.info("Workspace watcher started.");

    // Show current DB state immediately (often empty) so the UI is not blocked
    // on a full directory walk + thumbnail queue.
    await _emitSnapshot();

    final int generation = _scanGeneration;
    unawaited(_runInitialScanInBackground(generation));
  }

  /// Walks the tree asynchronously; list rows appear in batches via [_emitSnapshot].
  Future<void> _runInitialScanInBackground(int generation) async {
    int scannedCount = 0;
    _initialDirectoryScanActive = true;
    _snapshotNotifyDeferredUntilScanIdle = false;
    try {
      scannedCount = await _scanAllExistingFiles(generation);
      if (_disposed || generation != _scanGeneration) {
        return;
      }
      if (scannedCount > 0) {
        await _emitSnapshot();
      }
      _logger.info("Initial scan completed. Imported files: $scannedCount");
    } catch (error, stackTrace) {
      _logger.severe("Initial scan failed: $error", error, stackTrace);
    } finally {
      _initialDirectoryScanActive = false;
      if (!_disposed && generation == _scanGeneration) {
        final bool pendingDeferred = _snapshotNotifyDeferredUntilScanIdle;
        _snapshotNotifyDeferredUntilScanIdle = false;
        if (pendingDeferred && scannedCount == 0) {
          await _emitSnapshot();
        }
      }
    }
  }

  bool get _scanShouldPause => _playoutActive || _previewPlaying;

  /// Pauses the background scan and thumbnail queue during playout so that
  /// ffprobe and ffmpeg processes don't compete with the media player for
  /// disk I/O on the same drive.
  void setPlayoutActive(bool active) {
    _playoutActive = active;
    _thumbnailService.setScanPaused(active);
    _logger.fine(
      active
          ? "Playout started — pausing ingestion scan and thumbnails."
          : "Playout ended — resuming ingestion scan and thumbnails.",
    );
  }

  /// Pauses only the scan loop (not thumbnails) while a preview video is
  /// actively playing in the dashboard.
  void setPreviewPlaying(bool playing) {
    _previewPlaying = playing;
  }

  Future<void> stop() async {
    _logger.info("Stopping ingestion service.");
    await _watchSubscription?.cancel();
    _watchSubscription = null;
    if (_disposed) {
      _cancelAllModifyDebounces();
    } else {
      await _flushPendingModifyUpserts();
    }
    await _workspaceWatcher.stop();
  }

  Future<void> refreshIgnoredFolders() async {
    if (_repository == null) {
      return;
    }
    await _refreshIgnoredFolders();
  }

  /// After the DB row for a master file is removed (e.g. trash/move), drop it from
  /// the live snapshot, remove the sidecar thumbnail, and notify listeners.
  Future<void> removeMasterFromSnapshotAfterDbDelete(String storedMasterPath) async {
    await _thumbnailService.deleteThumbnailForVideoPath(
      _absoluteVideoPath(storedMasterPath),
    );
    _snapshotByPath.remove(storedMasterPath);
    await _emitSnapshot();
  }

  Future<void> dispose() async {
    _disposed = true;
    _snapshotDebounce?.cancel();
    _snapshotDebounce = null;
    await stop();
    await _workspaceWatcher.dispose();
    await _mediaController.close();
    await _thumbnailService.dispose();
  }

  static const int _scanEmitBatchSize = 50;

  int _scanProbeConcurrency = IngestionConcurrencyDefaults.probeDefault;

  /// Yields until neither playout nor preview playback is active.
  Future<void> _awaitUnpaused() async {
    while (_scanShouldPause && !_disposed) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  Future<int> _scanAllExistingFiles(int generation) async {
    final MediaRepository repository = _requireRepository();
    final String workspacePath = _requireWorkspacePath();
    int importedCount = 0;

    final Directory root = Directory(workspacePath);
    if (!await root.exists()) {
      _logger.warning("Workspace root does not exist: $workspacePath");
      return importedCount;
    }

    final List<String> probeChunk = <String>[];

    Future<void> flushProbeChunk() async {
      if (probeChunk.isEmpty) {
        return;
      }
      final List<String> paths = List<String>.from(probeChunk);
      probeChunk.clear();
      await _awaitUnpaused();
      if (_disposed || generation != _scanGeneration) {
        return;
      }
      final List<Future<_MasterFileGatherResult?>> probeFutures =
          paths.map(_gatherForUpsert).toList();
      final List<_MasterFileGatherResult?> gathered =
          await Future.wait(probeFutures);
      for (final _MasterFileGatherResult? g in gathered) {
        if (_disposed || generation != _scanGeneration) {
          return;
        }
        if (g == null) {
          continue;
        }
        final bool changed = await _commitUpsertFromGathered(repository, g);
        if (!changed) {
          continue;
        }
        importedCount++;
        if (importedCount == 1 || importedCount % _scanEmitBatchSize == 0) {
          await _emitSnapshot();
        }
      }
    }

    await for (final FileSystemEntity entity in root.list(
      recursive: true,
      followLinks: false,
    )) {
      if (_disposed || generation != _scanGeneration) {
        break;
      }
      if (entity is! File) {
        continue;
      }
      if (_isIgnoredPath(entity.path)) {
        continue;
      }
      if (!isSupportedVideoPath(entity.path)) {
        continue;
      }
      probeChunk.add(entity.path);
      if (probeChunk.length >= _scanProbeConcurrency) {
        await flushProbeChunk();
      }
    }
    await flushProbeChunk();
    return importedCount;
  }

  Future<void> _handleWatchEvent(WatchEvent event) async {
    if (_disposed) {
      return;
    }
    if (_isIgnoredPath(event.path)) {
      return;
    }
    if (!isSupportedVideoPath(event.path)) {
      // _logger.finer("Ignored non-video path: ${event.path}");
      return;
    }
    _logger.fine("Watch event ${event.type} for path: ${event.path}");

    if (event.type == ChangeType.REMOVE) {
      _cancelModifyDebounceForPath(event.path);
      final MediaRepository repository = _requireRepository();
      final String storedPath = _storedPathForEvent(event.path);
      await _thumbnailService.deleteThumbnailForVideoPath(
        _absoluteVideoPath(storedPath),
      );
      await repository.deleteByPath(storedPath);
      _snapshotByPath.remove(storedPath);
      _logger.info("Removed media record: $storedPath");
      await _emitSnapshot();
      return;
    }

    if (event.type == ChangeType.ADD) {
      // New path: ingest promptly; further growth is coalesced via MODIFY debounce.
      _cancelModifyDebounceForPath(event.path);
      await _processWatchedUpsert(event.path);
      return;
    }

    if (event.type == ChangeType.MODIFY) {
      _scheduleModifyUpsert(event.path);
    }
  }

  void _scheduleModifyUpsert(String eventPath) {
    final String key = _normalizedAbsolutePath(eventPath);
    _modifyDebounceTimers[key]?.cancel();
    _modifyDebounceAbsolutePaths[key] = eventPath;
    _modifyDebounceTimers[key] = Timer(_modifyDebounceWindow, () {
      _modifyDebounceTimers.remove(key);
      final String? path = _modifyDebounceAbsolutePaths.remove(key);
      if (path == null || _disposed) {
        return;
      }
      _logger.fine(
        "MODIFY debounce fired for $path "
        "(${_modifyDebounceWindow.inMilliseconds}ms quiet).",
      );
      unawaited(_processWatchedUpsert(path));
    });
  }

  void _cancelModifyDebounceForPath(String eventPath) {
    final String key = _normalizedAbsolutePath(eventPath);
    _modifyDebounceTimers.remove(key)?.cancel();
    _modifyDebounceAbsolutePaths.remove(key);
  }

  void _cancelAllModifyDebounces() {
    for (final Timer timer in _modifyDebounceTimers.values) {
      timer.cancel();
    }
    _modifyDebounceTimers.clear();
    _modifyDebounceAbsolutePaths.clear();
  }

  Future<void> _flushPendingModifyUpserts() async {
    final List<String> paths = _modifyDebounceAbsolutePaths.values.toList();
    _cancelAllModifyDebounces();
    for (final String path in paths) {
      if (_disposed) {
        return;
      }
      await _processWatchedUpsert(path);
    }
  }

  Future<void> _processWatchedUpsert(String eventPath) async {
    if (_disposed) {
      return;
    }
    final MediaRepository repository = _requireRepository();
    final String storedPath = _storedPathForEvent(eventPath);
    await repository.clearUnreadableIssue(storedPath);
    final bool changed = await _upsertFromPath(
      repository: repository,
      filePath: eventPath,
    );
    _logger.info("Upserted media record: $storedPath");
    if (changed) {
      await _emitSnapshot();
    }
  }

  Future<_MasterFileGatherResult?> _gatherForUpsert(String filePath) async {
    final File file = File(filePath);
    if (!await file.exists()) {
      _logger.warning("Video path no longer exists: $filePath");
      return null;
    }
    final FileStat stat = await file.stat();
    final String absolutePath = _normalizedAbsolutePath(file.path);
    final String storedPath = _storedPathFromAbsolute(absolutePath);
    int? durationMs;
    double? knownDurationSecondsForThumbnail;
    if (stat.size > 0) {
      final MasterMediaFile? cached = _snapshotByPath[storedPath];
      final bool statUnchanged =
          cached != null &&
          cached.fileSizeBytes == stat.size &&
          cached.modifiedAtMs == stat.modified.millisecondsSinceEpoch;
      if (statUnchanged && cached.durationMs != null) {
        durationMs = cached.durationMs;
        knownDurationSecondsForThumbnail = cached.durationMs! / 1000.0;
      } else {
        final MediaDurationProbeResult probe =
            await MediaDurationProbe.probeSeconds(absolutePath);
        if (probe.ok) {
          durationMs = probe.durationMs;
          knownDurationSecondsForThumbnail = probe.durationSeconds;
        }
      }
    }
    return _MasterFileGatherResult(
      absolutePath: absolutePath,
      storedPath: storedPath,
      stat: stat,
      durationMs: durationMs,
      knownDurationSecondsForThumbnail: knownDurationSecondsForThumbnail,
    );
  }

  Future<bool> _commitUpsertFromGathered(
    MediaRepository repository,
    _MasterFileGatherResult g,
  ) async {
    await repository.upsertMasterMedia(
      filePath: g.storedPath,
      fileName: p.basename(g.absolutePath),
      fileSizeBytes: g.stat.size,
      modifiedAtMs: g.stat.modified.millisecondsSinceEpoch,
      createdAtMs: g.stat.changed.millisecondsSinceEpoch,
      durationMs: g.durationMs,
    );
    if (g.stat.size == 0) {
      await repository.setMediaIssue(g.storedPath, MediaIssue.empty);
    } else {
      await repository.clearEmptyIssue(g.storedPath);
    }
    final bool changed = await _updateSnapshotEntryFromRepository(
      repository,
      g.storedPath,
    );
    await _thumbnailService.requestThumbnail(
      g.absolutePath,
      knownDurationSeconds: g.knownDurationSecondsForThumbnail,
    );
    return changed;
  }

  Future<bool> _upsertFromPath({
    required MediaRepository repository,
    required String filePath,
  }) async {
    final _MasterFileGatherResult? gathered = await _gatherForUpsert(filePath);
    if (gathered == null) {
      return false;
    }
    return _commitUpsertFromGathered(repository, gathered);
  }

  Future<void> _emitSnapshot() async {
    final List<MasterMediaFile> current = _snapshotByPath.values.toList()
      ..sort((MasterMediaFile a, MasterMediaFile b) {
        final int byModified = b.modifiedAtMs.compareTo(a.modifiedAtMs);
        if (byModified != 0) {
          return byModified;
        }
        return a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase());
      });
    _logger.fine("Emitting media snapshot with ${current.length} item(s).");
    _mediaController.add(List<MasterMediaFile>.unmodifiable(current));
  }

  Future<void> _onThumbnailSettled(
    String absoluteVideoPath,
    String? failureDetail,
  ) async {
    if (_disposed) {
      return;
    }
    final MediaRepository repository = _requireRepository();
    final String storedPath = _storedPathFromAbsolute(absoluteVideoPath);
    if (failureDetail != null) {
      await repository.setMediaIssue(
        storedPath,
        MediaIssue.unreadable,
        detail: failureDetail,
      );
      final bool updated = await _updateSnapshotEntryFromRepository(
        repository,
        storedPath,
      );
      if (updated) {
        _scheduleDebouncedSnapshot();
      }
      return;
    }
    final int cleared = await repository.clearUnreadableIssue(storedPath);
    if (cleared > 0) {
      final bool updated = await _updateSnapshotEntryFromRepository(
        repository,
        storedPath,
      );
      if (updated) {
        _scheduleDebouncedSnapshot();
      }
    }
  }

  void _scheduleDebouncedSnapshot() {
    if (_initialDirectoryScanActive) {
      _snapshotNotifyDeferredUntilScanIdle = true;
      return;
    }
    _snapshotDebounce?.cancel();
    _snapshotDebounce = Timer(const Duration(milliseconds: 400), () {
      if (_disposed) {
        return;
      }
      unawaited(_emitSnapshot());
    });
  }

  MediaRepository _requireRepository() {
    final MediaRepository? repository = _repository;
    if (repository == null) {
      throw StateError("IngestionService is not initialized.");
    }
    return repository;
  }

  String _requireWorkspacePath() {
    final String? workspacePath = _workspacePath;
    if (workspacePath == null) {
      throw StateError("Workspace path is not initialized.");
    }
    return workspacePath;
  }

  static bool isSupportedVideoPath(String path) {
    final String extension = p.extension(path).toLowerCase();
    return supportedVideoExtensions.contains(extension);
  }

  String _normalizedAbsolutePath(String path) => p.normalize(p.absolute(path));

  String _storedPathFromAbsolute(String absolutePath) {
    return WorkspaceMediaPaths.storedMasterPath(
      _requireWorkspacePath(),
      absolutePath,
    );
  }

  String _storedPathForEvent(String path) =>
      _storedPathFromAbsolute(_normalizedAbsolutePath(path));

  String _absoluteVideoPath(String storedPath) {
    return WorkspaceMediaPaths.absoluteMasterPath(
      _requireWorkspacePath(),
      storedPath,
    );
  }

  Future<void> _loadSnapshotFromRepository() async {
    final MediaRepository repository = _requireRepository();
    final List<MasterMediaFile> current = await repository.listAll();
    _snapshotByPath
      ..clear()
      ..addEntries(
        current.map(
          (MasterMediaFile item) =>
              MapEntry<String, MasterMediaFile>(item.filePath, item),
        ),
      );
  }

  Future<bool> _updateSnapshotEntryFromRepository(
    MediaRepository repository,
    String normalizedPath,
  ) async {
    final MasterMediaFile? latest = await repository.getMasterByPath(
      normalizedPath,
    );
    final MasterMediaFile? previous = _snapshotByPath[normalizedPath];
    if (latest == null) {
      final bool removed = _snapshotByPath.remove(normalizedPath) != null;
      return removed;
    }
    _snapshotByPath[normalizedPath] = latest;
    final bool same = _isSameSnapshotRow(previous, latest);
    return !same;
  }

  bool _isSameSnapshotRow(MasterMediaFile? a, MasterMediaFile b) {
    if (a == null) {
      return false;
    }
    return a.id == b.id &&
        WorkspaceMediaPaths.normalizeStored(a.filePath) ==
            WorkspaceMediaPaths.normalizeStored(b.filePath) &&
        a.fileName == b.fileName &&
        a.fileSizeBytes == b.fileSizeBytes &&
        a.modifiedAtMs == b.modifiedAtMs &&
        a.createdAtMs == b.createdAtMs &&
        a.durationMs == b.durationMs &&
        a.mediaIssue == b.mediaIssue &&
        _normalizedIssueDetail(a.mediaIssueDetail) ==
            _normalizedIssueDetail(b.mediaIssueDetail);
  }

  String _normalizedIssueDetail(String? detail) {
    return (detail ?? "")
        .replaceAll("\r\n", "\n")
        .replaceAll("\r", "\n")
        .trim();
  }

  Future<void> _refreshIgnoredFolders() async {
    final MediaRepository repository = _requireRepository();
    _ignoredRelativeFolders = (await repository.listIgnoredFolders())
        .map((String folder) => folder.replaceAll("\\", "/"))
        .toSet();
  }

  bool _isIgnoredPath(String path) {
    final String workspacePath = _requireWorkspacePath();
    final String normalizedAbsolutePath = _normalizedAbsolutePath(
      path,
    ).replaceAll("\\", "/");
    final String normalizedWorkspace = _normalizedAbsolutePath(
      workspacePath,
    ).replaceAll("\\", "/");
    final String relativePath = p
        .relative(normalizedAbsolutePath, from: normalizedWorkspace)
        .replaceAll("\\", "/");
    for (final String ignored in _ignoredRelativeFolders) {
      if (relativePath == ignored || relativePath.startsWith("$ignored/")) {
        return true;
      }
    }
    return false;
  }
}
