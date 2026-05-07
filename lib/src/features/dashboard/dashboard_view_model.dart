import "dart:async";

import "package:file_picker/file_picker.dart";
import "package:flutter/foundation.dart";
import "package:logging/logging.dart";

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
  final Logger _logger = Logger("DashboardViewModel");
  StreamSubscription<List<MasterMediaFile>>? _mediaSubscription;

  bool _isLoading = false;
  String? _workspacePath;
  List<MasterMediaFile> _mediaFiles = <MasterMediaFile>[];
  final Map<int, Set<String>> _tagsByMediaId = <int, Set<String>>{};
  int? _selectedMediaId;
  String? _activeTagFilter;

  bool get isLoading => _isLoading;
  String? get workspacePath => _workspacePath;
  List<MasterMediaFile> get mediaFiles => _mediaFiles;
  int? get selectedMediaId => _selectedMediaId;
  String? get activeTagFilter => _activeTagFilter;
  MasterMediaFile? get selectedMedia {
    final int? id = _selectedMediaId;
    if (id == null) {
      return null;
    }
    for (final MasterMediaFile file in _mediaFiles) {
      if (file.id == id) {
        return file;
      }
    }
    return null;
  }

  List<MasterMediaFile> get visibleMediaFiles {
    final String? filter = _activeTagFilter;
    if (filter == null || filter.isEmpty) {
      return _mediaFiles;
    }
    return _mediaFiles
        .where((MasterMediaFile file) => tagsForMedia(file.id).contains(filter))
        .toList();
  }

  Set<String> tagsForMedia(int mediaId) =>
      _tagsByMediaId[mediaId] ?? <String>{};

  Future<void> initialize() async {
    _logger.info("Initializing dashboard state.");
    _isLoading = true;
    notifyListeners();

    final WorkspaceSession? session = await _workspaceService.restoreWorkspace();
    if (session != null) {
      _logger.info("Restored workspace: ${session.workspace.rootPath}");
      await _startSession(session);
    } else {
      _logger.info("No workspace found to restore.");
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> pickAndSetWorkspace() async {
    final String? selectedDirectory = await FilePicker.getDirectoryPath(
      dialogTitle: "Select Workspace Directory",
    );
    if (selectedDirectory == null || selectedDirectory.isEmpty) {
      _logger.info("Workspace selection cancelled.");
      return;
    }

    _isLoading = true;
    notifyListeners();
    final WorkspaceSession session =
        await _workspaceService.setWorkspace(selectedDirectory);
    _logger.info("Workspace set to: $selectedDirectory");
    await _startSession(session);
    _isLoading = false;
    notifyListeners();
  }

  Future<void> _startSession(WorkspaceSession session) async {
    _workspacePath = session.workspace.rootPath;
    await _mediaSubscription?.cancel();
    _mediaSubscription = _ingestionService.mediaFiles.listen((List<MasterMediaFile> files) {
      _mediaFiles = files;
      final Set<int> currentIds = files.map((MasterMediaFile file) => file.id).toSet();
      _tagsByMediaId.removeWhere((int key, _) => !currentIds.contains(key));
      if (_selectedMediaId != null && !currentIds.contains(_selectedMediaId)) {
        _selectedMediaId = null;
      }
      if (_activeTagFilter != null) {
        final bool filterStillExists = files.any(
          (MasterMediaFile file) => tagsForMedia(file.id).contains(_activeTagFilter),
        );
        if (!filterStillExists) {
          _activeTagFilter = null;
        }
      }
      _logger.info("Dashboard received ${files.length} media item(s).");
      notifyListeners();
    });
    await _ingestionService.start(
      workspacePath: session.workspace.rootPath,
      repository: session.mediaRepository,
    );
  }

  @visibleForTesting
  void setStateForTest({
    bool? isLoading,
    String? workspacePath,
    List<MasterMediaFile>? mediaFiles,
    int? selectedMediaId,
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
    if (selectedMediaId != null) {
      _selectedMediaId = selectedMediaId;
    }
    notifyListeners();
  }

  void selectMedia(int mediaId) {
    _selectedMediaId = mediaId;
    notifyListeners();
  }

  void addTagToSelectedMedia(String tag) {
    final int? mediaId = _selectedMediaId;
    if (mediaId == null) {
      return;
    }
    final String normalized = tag.trim();
    if (normalized.isEmpty) {
      return;
    }
    final Set<String> tags = _tagsByMediaId.putIfAbsent(mediaId, () => <String>{});
    tags.add(normalized);
    notifyListeners();
  }

  void removeTagFromSelectedMedia(String tag) {
    final int? mediaId = _selectedMediaId;
    if (mediaId == null) {
      return;
    }
    _tagsByMediaId[mediaId]?.remove(tag);
    notifyListeners();
  }

  void toggleTagFilter(String tag) {
    if (_activeTagFilter == tag) {
      _activeTagFilter = null;
    } else {
      _activeTagFilter = tag;
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
