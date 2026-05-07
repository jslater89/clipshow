import "dart:async";
import "dart:io";

import "package:logging/logging.dart";
import "package:path/path.dart" as p;
import "package:watcher/watcher.dart";

import "../data/media_repository.dart";
import "../media/master_media_file.dart";
import "thumbnail_service.dart";
import "workspace_watcher.dart";

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

  Stream<List<MasterMediaFile>> get mediaFiles => _mediaController.stream;

  Future<void> start({
    required String workspacePath,
    required MediaRepository repository,
  }) async {
    _logger.info("Starting ingestion for workspace: $workspacePath");
    _repository = repository;
    _workspacePath = workspacePath;
    final int scannedCount = await _scanAllExistingFiles();
    await _emitSnapshot();
    _logger.info("Initial scan completed. Imported files: $scannedCount");

    await _watchSubscription?.cancel();
    _workspaceWatcher.start(workspacePath);
    _watchSubscription = _workspaceWatcher.events.listen(_handleWatchEvent);
    _logger.info("Workspace watcher started.");
  }

  Future<void> stop() async {
    _logger.info("Stopping ingestion service.");
    await _watchSubscription?.cancel();
    _watchSubscription = null;
    await _workspaceWatcher.stop();
  }

  Future<void> dispose() async {
    await stop();
    await _workspaceWatcher.dispose();
    await _mediaController.close();
  }

  Future<int> _scanAllExistingFiles() async {
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
    }
    return importedCount;
  }

  Future<void> _handleWatchEvent(WatchEvent event) async {
    final MediaRepository repository = _requireRepository();
    _logger.fine("Watch event ${event.type} for path: ${event.path}");
    if (!isSupportedVideoPath(event.path)) {
      _logger.finer("Ignored non-video path: ${event.path}");
      return;
    }

    if (event.type == ChangeType.REMOVE) {
      await _thumbnailService.deleteThumbnailForVideoPath(
        _normalizedPath(event.path),
      );
      await repository.deleteByPath(_normalizedPath(event.path));
      _logger.info("Removed media record: ${_normalizedPath(event.path)}");
      await _emitSnapshot();
      return;
    }

    if (event.type == ChangeType.ADD || event.type == ChangeType.MODIFY) {
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
    await repository.upsertMasterMedia(
      filePath: _normalizedPath(file.path),
      fileName: p.basename(file.path),
      fileSizeBytes: stat.size,
      modifiedAtMs: stat.modified.millisecondsSinceEpoch,
      createdAtMs: stat.changed.millisecondsSinceEpoch,
    );
    await _thumbnailService.generateThumbnail(_normalizedPath(file.path));
  }

  Future<void> _emitSnapshot() async {
    final MediaRepository repository = _requireRepository();
    final List<MasterMediaFile> current = await repository.listAll();
    _logger.fine("Emitting media snapshot with ${current.length} item(s).");
    _mediaController.add(current);
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
