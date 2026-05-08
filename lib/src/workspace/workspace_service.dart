import "dart:io";

import "package:logging/logging.dart";
import "package:sqflite/sqflite.dart";

import 'package:obs_clipshow/src/data/app_database.dart';
import 'package:obs_clipshow/src/data/media_repository.dart';
import 'package:obs_clipshow/src/media/workspace.dart';
import 'package:obs_clipshow/src/workspace/workspace_preferences.dart';

class WorkspaceSession {
  const WorkspaceSession({
    required this.workspace,
    required this.database,
    required this.mediaRepository,
  });

  final Workspace workspace;
  final Database database;
  final MediaRepository mediaRepository;
}

class WorkspaceService {
  WorkspaceService({
    required AppDatabase appDatabase,
    required WorkspacePreferences workspacePreferences,
  })  : _appDatabase = appDatabase,
        _workspacePreferences = workspacePreferences;

  final AppDatabase _appDatabase;
  final WorkspacePreferences _workspacePreferences;
  final Logger _logger = Logger("WorkspaceService");
  WorkspaceSession? _session;

  WorkspaceSession? get currentSession => _session;

  Future<WorkspaceSession?> restoreWorkspace() async {
    final String? path = await _workspacePreferences.loadWorkspacePath();
    if (path == null) {
      _logger.info("No saved workspace path found.");
      return null;
    }
    final Directory directory = Directory(path);
    if (!await directory.exists()) {
      _logger.warning("Saved workspace missing on disk: $path");
      await _workspacePreferences.saveWorkspacePath(null);
      return null;
    }
    _logger.info("Restoring workspace from saved path: $path");
    return setWorkspace(path);
  }

  Future<WorkspaceSession> setWorkspace(String rootPath) async {
    final Workspace workspace = Workspace(rootPath: rootPath);
    _logger.info("Opening workspace database at: ${workspace.databasePath}");
    await _session?.database.close();
    final Database database = await _appDatabase.openForWorkspace(workspace);
    final MediaRepository mediaRepository = MediaRepository(database);
    final WorkspaceSession next = WorkspaceSession(
      workspace: workspace,
      database: database,
      mediaRepository: mediaRepository,
    );
    _session = next;
    await _workspacePreferences.saveWorkspacePath(rootPath);
    return next;
  }
}
