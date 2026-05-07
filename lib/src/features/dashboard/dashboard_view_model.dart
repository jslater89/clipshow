import "dart:async";

import "package:file_picker/file_picker.dart";
import "package:flutter/foundation.dart";

import "../../data/app_database.dart";
import "../../ingestion/ingestion_service.dart";
import "../../ingestion/workspace_watcher.dart";
import "../../media/master_media_file.dart";
import "../../workspace/workspace_preferences.dart";
import "../../workspace/workspace_service.dart";

class DashboardViewModel extends ChangeNotifier {
  DashboardViewModel({
    required WorkspaceService workspaceService,
    required IngestionService ingestionService,
  })  : _workspaceService = workspaceService,
        _ingestionService = ingestionService;

  factory DashboardViewModel.create() {
    final WorkspaceService workspaceService = WorkspaceService(
      appDatabase: AppDatabase(),
      workspacePreferences: WorkspacePreferences(),
    );
    final IngestionService ingestionService = IngestionService(
      workspaceWatcher: WorkspaceWatcher(),
    );
    return DashboardViewModel(
      workspaceService: workspaceService,
      ingestionService: ingestionService,
    );
  }

  final WorkspaceService _workspaceService;
  final IngestionService _ingestionService;
  StreamSubscription<List<MasterMediaFile>>? _mediaSubscription;

  bool _isLoading = false;
  String? _workspacePath;
  List<MasterMediaFile> _mediaFiles = <MasterMediaFile>[];

  bool get isLoading => _isLoading;
  String? get workspacePath => _workspacePath;
  List<MasterMediaFile> get mediaFiles => _mediaFiles;

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    final WorkspaceSession? session = await _workspaceService.restoreWorkspace();
    if (session != null) {
      await _startSession(session);
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> pickAndSetWorkspace() async {
    final String? selectedDirectory = await FilePicker.getDirectoryPath(
      dialogTitle: "Select Workspace Directory",
    );
    if (selectedDirectory == null || selectedDirectory.isEmpty) {
      return;
    }

    _isLoading = true;
    notifyListeners();
    final WorkspaceSession session =
        await _workspaceService.setWorkspace(selectedDirectory);
    await _startSession(session);
    _isLoading = false;
    notifyListeners();
  }

  Future<void> _startSession(WorkspaceSession session) async {
    _workspacePath = session.workspace.rootPath;
    await _mediaSubscription?.cancel();
    await _ingestionService.start(
      workspacePath: session.workspace.rootPath,
      repository: session.mediaRepository,
    );
    _mediaSubscription = _ingestionService.mediaFiles.listen((List<MasterMediaFile> files) {
      _mediaFiles = files;
      notifyListeners();
    });
  }

  @visibleForTesting
  void setStateForTest({
    bool? isLoading,
    String? workspacePath,
    List<MasterMediaFile>? mediaFiles,
  }) {
    if (isLoading != null) {
      _isLoading = isLoading;
    }
    if (workspacePath != null) {
      _workspacePath = workspacePath;
    }
    if (mediaFiles != null) {
      _mediaFiles = mediaFiles;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_mediaSubscription?.cancel());
    unawaited(_ingestionService.dispose());
    super.dispose();
  }
}
