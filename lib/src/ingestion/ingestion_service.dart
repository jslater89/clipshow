import "dart:async";
import "dart:io";

import "package:path/path.dart" as p;
import "package:watcher/watcher.dart";

import "../data/media_repository.dart";
import "../media/master_media_file.dart";
import "workspace_watcher.dart";

class IngestionService {
  IngestionService({
    required WorkspaceWatcher workspaceWatcher,
  }) : _workspaceWatcher = workspaceWatcher;

  static const Set<String> supportedVideoExtensions = <String>{
    ".mp4",
    ".mov",
    ".mkv",
    ".avi",
    ".webm",
  };

  final WorkspaceWatcher _workspaceWatcher;
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
    _repository = repository;
    _workspacePath = workspacePath;
    await _scanAllExistingFiles();
    await _emitSnapshot();

    await _watchSubscription?.cancel();
    _workspaceWatcher.start(workspacePath);
    _watchSubscription = _workspaceWatcher.events.listen(_handleWatchEvent);
  }

  Future<void> stop() async {
    await _watchSubscription?.cancel();
    _watchSubscription = null;
    await _workspaceWatcher.stop();
  }

  Future<void> dispose() async {
    await stop();
    await _workspaceWatcher.dispose();
    await _mediaController.close();
  }

  Future<void> _scanAllExistingFiles() async {
    final MediaRepository repository = _requireRepository();
    final String workspacePath = _requireWorkspacePath();

    final Directory root = Directory(workspacePath);
    if (!await root.exists()) {
      return;
    }

    await for (final FileSystemEntity entity
        in root.list(recursive: true, followLinks: false)) {
      if (entity is! File || !isSupportedVideoPath(entity.path)) {
        continue;
      }
      await _upsertFromPath(
        repository: repository,
        filePath: entity.path,
      );
    }
  }

  Future<void> _handleWatchEvent(WatchEvent event) async {
    final MediaRepository repository = _requireRepository();
    if (!isSupportedVideoPath(event.path)) {
      return;
    }

    if (event.type == ChangeType.REMOVE) {
      await repository.deleteByPath(_normalizedPath(event.path));
      await _emitSnapshot();
      return;
    }

    if (event.type == ChangeType.ADD || event.type == ChangeType.MODIFY) {
      await _upsertFromPath(
        repository: repository,
        filePath: event.path,
      );
      await _emitSnapshot();
    }
  }

  Future<void> _upsertFromPath({
    required MediaRepository repository,
    required String filePath,
  }) async {
    final File file = File(filePath);
    if (!await file.exists()) {
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
  }

  Future<void> _emitSnapshot() async {
    final MediaRepository repository = _requireRepository();
    _mediaController.add(await repository.listAll());
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
