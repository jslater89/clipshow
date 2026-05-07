import "dart:io";

import "package:sqflite/sqflite.dart";

import "../data/app_database.dart";
import "../data/media_repository.dart";
import "../media/workspace.dart";
import "workspace_preferences.dart";

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
  WorkspaceSession? _session;

  WorkspaceSession? get currentSession => _session;

  Future<WorkspaceSession?> restoreWorkspace() async {
    final String? path = await _workspacePreferences.loadWorkspacePath();
    if (path == null) {
      return null;
    }
    final Directory directory = Directory(path);
    if (!await directory.exists()) {
      await _workspacePreferences.saveWorkspacePath(null);
      return null;
    }
    return setWorkspace(path);
  }

  Future<WorkspaceSession> setWorkspace(String rootPath) async {
    final Workspace workspace = Workspace(rootPath: rootPath);
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
