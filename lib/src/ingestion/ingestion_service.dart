import "dart:async";
import "dart:io";

import "package:logging/logging.dart";
import "package:path/path.dart" as p;
import "package:watcher/watcher.dart";

import 'package:obs_clipshow/src/data/media_repository.dart';
import 'package:obs_clipshow/src/media/master_media_file.dart';
import 'package:obs_clipshow/src/ingestion/thumbnail_service.dart';
import 'package:obs_clipshow/src/ingestion/workspace_watcher.dart';

class IngestionService {
  IngestionService({
    required WorkspaceWatcher workspaceWatcher,
    ThumbnailService? thumbnailService,
  })  : _workspaceWatcher = workspaceWatcher,
        _thumbnailService = thumbnailService ?? ThumbnailService();

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
  int _scanGeneration = 0;
  Timer? _snapshotDebounce;

  Stream<List<MasterMediaFile>> get mediaFiles => _mediaController.stream;

  /// Fires when a thumbnail file has been written for a video path (for UI refresh).
  Stream<String> get thumbnailReady => _thumbnailService.thumbnailReady;

  Future<void> start({
    required String workspacePath,
    required MediaRepository repository,
  }) async {
    _logger.info("Starting ingestion for workspace: $workspacePath");
    _repository = repository;
    _workspacePath = workspacePath;
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
    try {
      final int scannedCount = await _scanAllExistingFiles(generation);
      if (_disposed || generation != _scanGeneration) {
        return;
      }
      await _emitSnapshot();
      _logger.info("Initial scan completed. Imported files: $scannedCount");
    } catch (error, stackTrace) {
      _logger.severe("Initial scan failed: $error", error, stackTrace);
    }
  }

  Future<void> stop() async {
    _logger.info("Stopping ingestion service.");
    await _watchSubscription?.cancel();
    _watchSubscription = null;
    await _workspaceWatcher.stop();
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

  Future<int> _scanAllExistingFiles(int generation) async {
    final MediaRepository repository = _requireRepository();
    final String workspacePath = _requireWorkspacePath();
    int importedCount = 0;

    final Directory root = Directory(workspacePath);
    if (!await root.exists()) {
      _logger.warning("Workspace root does not exist: $workspacePath");
      return importedCount;
    }

    await for (final FileSystemEntity entity
        in root.list(recursive: true, followLinks: false)) {
      if (_disposed || generation != _scanGeneration) {
        break;
      }
      if (entity is! File) {
        continue;
      }
      if (!isSupportedVideoPath(entity.path)) {
        continue;
      }
      await _upsertFromPath(
        repository: repository,
        filePath: entity.path,
      );
      importedCount++;
      if (importedCount == 1 || importedCount % _scanEmitBatchSize == 0) {
        await _emitSnapshot();
      }
    }
    return importedCount;
  }

  Future<void> _handleWatchEvent(WatchEvent event) async {
    if (_disposed) {
      return;
    }
    final MediaRepository repository = _requireRepository();
    if (!isSupportedVideoPath(event.path)) {
      // _logger.finer("Ignored non-video path: ${event.path}");
      return;
    }
    _logger.fine("Watch event ${event.type} for path: ${event.path}");

    if (event.type == ChangeType.REMOVE) {
      final String normalizedPath = _normalizedPath(event.path);
      await _thumbnailService.deleteThumbnailForVideoPath(normalizedPath);
      await repository.deleteByPath(normalizedPath);
      _logger.info("Removed media record: ${_normalizedPath(event.path)}");
      await _emitSnapshot();
      return;
    }

    if (event.type == ChangeType.ADD || event.type == ChangeType.MODIFY) {
      final String normalizedPath = _normalizedPath(event.path);
      await repository.clearUnreadableIssue(normalizedPath);
      await _upsertFromPath(
        repository: repository,
        filePath: event.path,
      );
      _logger.info("Upserted media record: ${_normalizedPath(event.path)}");
      await _emitSnapshot();
    }
  }

  Future<void> _upsertFromPath({
    required MediaRepository repository,
    required String filePath,
  }) async {
    final File file = File(filePath);
    if (!await file.exists()) {
      _logger.warning("Video path no longer exists: $filePath");
      return;
    }
    final FileStat stat = await file.stat();
    final String normalizedPath = _normalizedPath(file.path);
    await repository.upsertMasterMedia(
      filePath: normalizedPath,
      fileName: p.basename(file.path),
      fileSizeBytes: stat.size,
      modifiedAtMs: stat.modified.millisecondsSinceEpoch,
      createdAtMs: stat.changed.millisecondsSinceEpoch,
    );
    if (stat.size == 0) {
      await repository.setMediaIssue(normalizedPath, MediaIssue.empty);
    } else {
      await repository.clearEmptyIssue(normalizedPath);
    }
    _thumbnailService.requestThumbnail(normalizedPath);
  }

  Future<void> _emitSnapshot() async {
    final MediaRepository repository = _requireRepository();
    final List<MasterMediaFile> current = await repository.listAll();
    _logger.fine("Emitting media snapshot with ${current.length} item(s).");
    _mediaController.add(current);
  }

  Future<void> _onThumbnailSettled(
    String normalizedPath,
    String? failureDetail,
  ) async {
    if (_disposed) {
      return;
    }
    final MediaRepository repository = _requireRepository();
    if (failureDetail != null) {
      await repository.setMediaIssue(
        normalizedPath,
        MediaIssue.unreadable,
        detail: failureDetail,
      );
      _scheduleDebouncedSnapshot();
      return;
    }
    final int cleared = await repository.clearUnreadableIssue(normalizedPath);
    if (cleared > 0) {
      _scheduleDebouncedSnapshot();
    }
  }

  void _scheduleDebouncedSnapshot() {
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

  String _normalizedPath(String path) => p.normalize(p.absolute(path));
}
