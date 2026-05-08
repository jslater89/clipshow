import "dart:async";
import "dart:convert";
import "dart:io";

import "package:file_picker/file_picker.dart";
import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:path/path.dart" as p;

import "package:obs_clipshow/src/data/app_database.dart";
import "package:obs_clipshow/src/data/media_repository.dart";
import "package:obs_clipshow/src/ingestion/ingestion_service.dart";
import "package:obs_clipshow/src/ingestion/thumbnail_service.dart";
import "package:obs_clipshow/src/ingestion/workspace_watcher.dart";
import "package:obs_clipshow/src/media/master_media_file.dart";
import "package:obs_clipshow/src/media/media_list_item.dart";
import "package:obs_clipshow/src/workspace/workspace_settings.dart";
import "package:obs_clipshow/src/workspace/workspace_preferences.dart";
import "package:obs_clipshow/src/workspace/workspace_service.dart";

class DashboardViewModel extends ChangeNotifier {
  static const int _savedTagApplyBatchSize = 100;

  DashboardViewModel({
    required WorkspaceService workspaceService,
    required IngestionService ingestionService,
  }) : _workspaceService = workspaceService,
       _ingestionService = ingestionService;

  factory DashboardViewModel.create() {
    final WorkspaceService workspaceService = WorkspaceService(
      appDatabase: AppDatabase(),
      workspacePreferences: WorkspacePreferences(),
    );
    final ThumbnailService thumbnailService = ThumbnailService();
    final IngestionService ingestionService = IngestionService(
      workspaceWatcher: WorkspaceWatcher(),
      thumbnailService: thumbnailService,
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
  StreamSubscription<String>? _thumbnailSubscription;
  MediaRepository? _mediaRepository;

  bool _isLoading = false;
  String? _workspacePath;
  List<MasterMediaFile> _mediaFiles = <MasterMediaFile>[];
  List<MediaListItem> _allItems = <MediaListItem>[];
  List<MediaListItem> _visibleItems = <MediaListItem>[];
  final Map<String, Set<String>> _tagsByItemKey = <String, Set<String>>{};
  final Set<String> _activeTagFilters = <String>{};
  final List<String> _allTags = <String>[];
  final List<String> _savedTags = <String>[];
  int _previewPositionMs = 0;
  int? _markInMs;
  int? _markOutMs;
  String _tagSearchQuery = "";
  String _fileNameSearchQuery = "";
  bool _fileSearchUsesFullPath = false;
  String? _selectedItemKey;
  bool _showUntaggedOnly = false;
  WorkspaceSettingsBundle? _workspaceSettings;

  bool get isLoading => _isLoading;
  String? get workspacePath => _workspacePath;
  List<MasterMediaFile> get mediaFiles => _mediaFiles;
  List<MediaListItem> get visibleItems => _visibleItems;
  List<String> get allTags => _allTags;
  List<String> get savedTags => _savedTags;
  Set<String> get activeTagFilters => _activeTagFilters;
  int? get markInMs => _markInMs;
  int? get markOutMs => _markOutMs;
  int get previewPositionMs => _previewPositionMs;
  String get tagSearchQuery => _tagSearchQuery;
  String get fileNameSearchQuery => _fileNameSearchQuery;
  bool get fileSearchUsesFullPath => _fileSearchUsesFullPath;
  bool get hasActiveItemFilters =>
      _showUntaggedOnly ||
      _activeTagFilters.isNotEmpty ||
      _tagSearchQuery.trim().isNotEmpty ||
      _fileNameSearchQuery.trim().isNotEmpty;
  bool get showUntaggedOnly => _showUntaggedOnly;
  String? get selectedItemKey => _selectedItemKey;
  TelestratorDefaults get telestratorDefaults =>
      _workspaceSettings?.telestratorDefaults ?? TelestratorDefaults.fallback();
  DecoderConfig get decoderConfig =>
      _workspaceSettings?.decoderConfig ?? const DecoderConfig.fallback();
  MdkLogVerbosity get mdkLogVerbosity =>
      _workspaceSettings?.mdkLogVerbosity ?? MdkLogVerbosity.warning;
  ObsSceneSwitchConfig? get obsSceneSwitchConfig =>
      _workspaceSettings?.obsSceneSwitchConfig;
  List<WebhookSceneSwitchConfig> get webhookSceneSwitchConfigs =>
      _workspaceSettings?.webhookSceneSwitchConfigs ??
      <WebhookSceneSwitchConfig>[];
  List<String> get ignoredFolders =>
      _workspaceSettings?.ignoredFolders ?? <String>[];
  MasterMediaFile? get selectedMedia {
    final MediaListItem? item = selectedItem;
    if (item == null || item.type != MediaListItemType.master) {
      return null;
    }
    return item.master;
  }

  MediaListItem? get selectedItem {
    final String? key = _selectedItemKey;
    if (key == null) {
      return null;
    }
    for (final MediaListItem item in _allItems) {
      if (item.stableKey == key) {
        return item;
      }
    }
    return null;
  }

  Set<String> tagsForItem(MediaListItem item) =>
      _tagsByItemKey[item.stableKey] ?? <String>{};

  List<String> tagSuggestionsFor(String query) {
    final Iterable<String> userTags = _allTags.where(_isUserTag);
    final String normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return userTags.take(20).toList();
    }
    return userTags
        .where((String tag) => tag.toLowerCase().contains(normalized))
        .take(20)
        .toList();
  }

  Future<void> initialize() async {
    _logger.info("Initializing dashboard state.");
    _isLoading = true;
    notifyListeners();

    final WorkspaceSession? session = await _workspaceService
        .restoreWorkspace();
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
    final WorkspaceSession session = await _workspaceService.setWorkspace(
      selectedDirectory,
    );
    _logger.info("Workspace set to: $selectedDirectory");
    await _startSession(session);
    _isLoading = false;
    notifyListeners();
  }

  Future<void> _startSession(WorkspaceSession session) async {
    _mediaRepository = session.mediaRepository;
    _workspacePath = session.workspace.rootPath;
    await _mediaSubscription?.cancel();
    await _thumbnailSubscription?.cancel();
    _thumbnailSubscription = _ingestionService.thumbnailReady.listen(
      (String _) => notifyListeners(),
    );
    _mediaSubscription = _ingestionService.mediaFiles.listen((
      List<MasterMediaFile> files,
    ) {
      _mediaFiles = files;
      _logger.info("Dashboard received ${files.length} media item(s).");
      unawaited(_reloadFromRepository());
    });
    await _ingestionService.start(
      workspacePath: session.workspace.rootPath,
      repository: session.mediaRepository,
    );
    await _loadWorkspaceSettings();
    await _reloadFromRepository();
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
      _allItems = mediaFiles.map(MediaListItem.master).toList();
      _visibleItems = List<MediaListItem>.from(_allItems);
    }
    if (selectedMediaId != null) {
      _selectedItemKey = "m:$selectedMediaId";
    }
    notifyListeners();
  }

  @visibleForTesting
  void setItemsForTest({
    required List<MediaListItem> items,
    Map<String, Set<String>>? tagsByItemKey,
  }) {
    _allItems = items;
    _visibleItems = List<MediaListItem>.from(items);
    _tagsByItemKey
      ..clear()
      ..addAll(tagsByItemKey ?? <String, Set<String>>{});
    _applyFilters();
    notifyListeners();
  }

  void selectItem(MediaListItem item) {
    _selectedItemKey = item.stableKey;
    _markInMs = null;
    _markOutMs = null;
    notifyListeners();
  }

  Future<void> addTagToSelectedMedia(String tag) async {
    final MediaListItem? item = selectedItem;
    if (item == null) {
      return;
    }
    final MediaRepository? repository = _mediaRepository;
    if (repository == null) {
      return;
    }
    final String normalized = repository.normalizeTag(tag);
    if (normalized.isEmpty) {
      return;
    }
    await repository.addTagToMedia(
      mediaType: item.type,
      mediaId: item.id,
      tag: normalized,
    );
    await _reloadFromRepository();
  }

  Future<void> removeTagFromSelectedMedia(String tag) async {
    final MediaListItem? item = selectedItem;
    final MediaRepository? repository = _mediaRepository;
    if (item == null || repository == null) {
      return;
    }
    await repository.removeTagFromMedia(
      mediaType: item.type,
      mediaId: item.id,
      tag: tag,
    );
    await _reloadFromRepository();
  }

  void toggleTagFilter(String tag) {
    if (_activeTagFilters.contains(tag)) {
      _activeTagFilters.remove(tag);
    } else {
      _activeTagFilters.add(tag);
    }
    _applyFilters();
    notifyListeners();
  }

  void addTagFilter(String tag) {
    final String normalized = tag.trim();
    if (normalized.isEmpty) {
      return;
    }
    final bool alreadySelected = _activeTagFilters.any(
      (String existing) => existing.toLowerCase() == normalized.toLowerCase(),
    );
    if (alreadySelected) {
      return;
    }
    _activeTagFilters.add(normalized);
    _applyFilters();
    notifyListeners();
  }

  void setTagSearchQuery(String query) {
    _tagSearchQuery = query;
    notifyListeners();
  }

  void setFileNameSearchQuery(String query) {
    _fileNameSearchQuery = query;
    _applyFilters();
    notifyListeners();
  }

  void toggleFileSearchScope() {
    _fileSearchUsesFullPath = !_fileSearchUsesFullPath;
    _applyFilters();
    notifyListeners();
  }

  void setShowUntaggedOnly(bool value) {
    _showUntaggedOnly = value;
    _applyFilters();
    notifyListeners();
  }

  Future<void> addSavedTag(String tag) async {
    final MediaRepository? repository = _mediaRepository;
    if (repository == null) {
      return;
    }
    await repository.addSavedTag(tag);
    await _reloadFromRepository();
  }

  Future<void> removeSavedTag(String tag) async {
    final MediaRepository? repository = _mediaRepository;
    if (repository == null) {
      return;
    }
    await repository.removeSavedTag(tag);
    await _reloadFromRepository();
  }

  Future<void> applySavedTagToSelectedMedia(String tag) async {
    await addTagToSelectedMedia(tag);
  }

  Future<void> applyAllSavedTagsToSelectedMedia() async {
    final MediaListItem? item = selectedItem;
    final MediaRepository? repository = _mediaRepository;
    if (item == null || repository == null || _savedTags.isEmpty) {
      return;
    }
    for (final String tag in _savedTags) {
      await repository.addTagToMedia(
        mediaType: item.type,
        mediaId: item.id,
        tag: tag,
      );
    }
    await _reloadFromRepository();
  }

  Future<int> applyAllSavedTagsToItems({required bool filteredOnly}) async {
    final MediaRepository? repository = _mediaRepository;
    if (repository == null || _savedTags.isEmpty) {
      return 0;
    }
    final List<MediaListItem> targetItems = List<MediaListItem>.from(
      filteredOnly ? _visibleItems : _allItems,
    );
    final List<String> savedTags = List<String>.from(_savedTags);
    if (targetItems.isEmpty) {
      return 0;
    }
    final List<String> savedTagsLower = savedTags
        .map((String tag) => tag.toLowerCase())
        .toList();
    final List<MediaListItem> itemsNeedingUpdate = <MediaListItem>[];
    for (final MediaListItem item in targetItems) {
      final Set<String> existingTagsLower =
          (_tagsByItemKey[item.stableKey] ?? <String>{})
              .map((String tag) => tag.toLowerCase())
              .toSet();
      final bool needsUpdate = savedTagsLower.any(
        (String tag) => !existingTagsLower.contains(tag),
      );
      if (needsUpdate) {
        itemsNeedingUpdate.add(item);
      }
    }
    if (itemsNeedingUpdate.isEmpty) {
      return 0;
    }
    for (int i = 0; i < itemsNeedingUpdate.length; i += _savedTagApplyBatchSize) {
      final int end = (i + _savedTagApplyBatchSize < itemsNeedingUpdate.length)
          ? i + _savedTagApplyBatchSize
          : itemsNeedingUpdate.length;
      final List<MediaListItem> batch = itemsNeedingUpdate.sublist(i, end);
      await repository.addTagsToItems(items: batch, tags: savedTags);
      await _refreshTagsForItems(batch, refreshAllTags: false);
    }
    _allTags
      ..clear()
      ..addAll(await repository.listAllTags());
    _applyFilters();
    notifyListeners();
    return itemsNeedingUpdate.length;
  }

  void markInAtCurrentPosition() {
    _markInMs = _previewPositionMs;
    if (_markOutMs != null && _markOutMs! <= _markInMs!) {
      _markOutMs = null;
    }
    notifyListeners();
  }

  void markOutAtCurrentPosition() {
    _markOutMs = _previewPositionMs;
    notifyListeners();
  }

  void setPreviewPositionMs(int positionMs) {
    _previewPositionMs = positionMs;
  }

  void saveClipFromCurrentMarks(BuildContext context) async {
    final error = await saveClipFromSelectedMaster();
    if (error != null && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<String?> saveClipFromSelectedMaster() async {
    final MediaRepository? repository = _mediaRepository;
    final MasterMediaFile? master = selectedMedia;
    if (repository == null || master == null) {
      return "Select a master file first.";
    }
    final int inMs = _markInMs ?? 0;
    final int? outMs = _markOutMs;
    if (outMs != null && outMs <= inMs) {
      return "Mark Out must be greater than Mark In.";
    }
    await repository.createClip(
      masterMediaId: master.id,
      inMs: inMs,
      outMs: outMs,
    );
    await _reloadFromRepository();
    return null;
  }

  Future<String?> deleteSelectedClip() async {
    final MediaRepository? repository = _mediaRepository;
    final MediaListItem? item = selectedItem;
    if (repository == null ||
        item == null ||
        item.type != MediaListItemType.clip) {
      return "Select a clip first.";
    }
    await repository.deleteClipById(item.id);
    await _reloadFromRepository();
    return null;
  }

  Future<void> _reloadFromRepository() async {
    final MediaRepository? repository = _mediaRepository;
    if (repository == null) {
      return;
    }
    final List<MediaListItem> items = await repository.listMixedItems();
    final Map<String, Set<String>> tagsByItemKey = await repository
        .listTagsForItems(items);
    _allItems = items;
    _tagsByItemKey
      ..clear()
      ..addAll(tagsByItemKey);
    _allTags
      ..clear()
      ..addAll(await repository.listAllTags());
    _savedTags
      ..clear()
      ..addAll(await repository.listSavedTags());
    if (_selectedItemKey != null &&
        !_allItems.any(
          (MediaListItem item) => item.stableKey == _selectedItemKey,
        )) {
      _selectedItemKey = null;
    }
    _applyFilters();
    notifyListeners();
  }

  Future<void> _loadWorkspaceSettings() async {
    final MediaRepository? repository = _mediaRepository;
    if (repository == null) {
      return;
    }
    _workspaceSettings = await repository.loadWorkspaceSettings();
  }

  Future<void> saveTelestratorDefaults(TelestratorDefaults value) async {
    final MediaRepository? repository = _mediaRepository;
    if (repository == null) {
      return;
    }
    await repository.saveTelestratorDefaults(value);
    await _loadWorkspaceSettings();
    notifyListeners();
  }

  Future<void> saveDecoderConfig(DecoderConfig value) async {
    final MediaRepository? repository = _mediaRepository;
    if (repository == null) {
      return;
    }
    await repository.saveDecoderConfig(value);
    await _loadWorkspaceSettings();
    notifyListeners();
  }

  Future<void> saveMdkLogVerbosity(MdkLogVerbosity value) async {
    final MediaRepository? repository = _mediaRepository;
    if (repository == null) {
      return;
    }
    await repository.saveMdkLogVerbosity(value);
    await _loadWorkspaceSettings();
    notifyListeners();
  }

  Future<void> saveObsSceneSwitchConfig(ObsSceneSwitchConfig? value) async {
    final MediaRepository? repository = _mediaRepository;
    if (repository == null) {
      return;
    }
    await repository.saveObsSceneSwitchConfig(value);
    await _loadWorkspaceSettings();
    notifyListeners();
  }

  Future<void> setObsSceneSwitchEnabled(bool enabled) async {
    final MediaRepository? repository = _mediaRepository;
    if (repository == null) {
      return;
    }
    await repository.setObsSceneSwitchEnabled(enabled);
    await _loadWorkspaceSettings();
    notifyListeners();
  }

  Future<void> addWebhookSceneSwitchConfig(WebhookSceneSwitchConfig value) async {
    final MediaRepository? repository = _mediaRepository;
    if (repository == null) {
      return;
    }
    await repository.addWebhookSceneSwitchConfig(value);
    await _loadWorkspaceSettings();
    notifyListeners();
  }

  Future<void> updateWebhookSceneSwitchConfig(
    WebhookSceneSwitchConfig value,
  ) async {
    final MediaRepository? repository = _mediaRepository;
    if (repository == null) {
      return;
    }
    await repository.updateWebhookSceneSwitchConfig(value);
    await _loadWorkspaceSettings();
    notifyListeners();
  }

  Future<void> deleteWebhookSceneSwitchConfig(int id) async {
    final MediaRepository? repository = _mediaRepository;
    if (repository == null) {
      return;
    }
    await repository.deleteWebhookSceneSwitchConfig(id);
    await _loadWorkspaceSettings();
    notifyListeners();
  }

  Future<void> setWebhookSceneSwitchEnabled(int id, bool enabled) async {
    final MediaRepository? repository = _mediaRepository;
    if (repository == null) {
      return;
    }
    await repository.setWebhookSceneSwitchEnabled(id, enabled);
    await _loadWorkspaceSettings();
    notifyListeners();
  }

  Future<void> addIgnoredFolder(String relativePath) async {
    final MediaRepository? repository = _mediaRepository;
    if (repository == null) {
      return;
    }
    await repository.addIgnoredFolder(relativePath);
    await _ingestionService.refreshIgnoredFolders();
    await _loadWorkspaceSettings();
    notifyListeners();
  }

  Future<void> removeIgnoredFolder(String relativePath) async {
    final MediaRepository? repository = _mediaRepository;
    if (repository == null) {
      return;
    }
    await repository.removeIgnoredFolder(relativePath);
    await _ingestionService.refreshIgnoredFolders();
    await _loadWorkspaceSettings();
    notifyListeners();
  }

  Future<void> exportWorkspace() async {
    final MediaRepository? repository = _mediaRepository;
    final String? workspaceRoot = _workspacePath;
    if (repository == null || workspaceRoot == null) {
      return;
    }
    final String? outputPath = await FilePicker.saveFile(
      dialogTitle: "Export Workspace JSON",
      fileName: "workspace_export.json",
      type: FileType.custom,
      allowedExtensions: <String>["json"],
    );
    if (outputPath == null || outputPath.trim().isEmpty) {
      return;
    }
    final List<MediaListItem> items = await repository.listMixedItems();
    final Map<String, Set<String>> tagsByItem = await repository.listTagsForItems(items);
    final WorkspaceSettingsBundle settings = await repository.loadWorkspaceSettings();
    final Map<String, Object?> payload = <String, Object?>{
      "workspacePath": workspaceRoot,
      "settings": <String, Object?>{
        "telestratorDefaults": <String, Object?>{
          "color1": settings.telestratorDefaults.colorOneArgb,
          "color2": settings.telestratorDefaults.colorTwoArgb,
          "color3": settings.telestratorDefaults.colorThreeArgb,
          "brushSize": settings.telestratorDefaults.brushSize,
          "enabledByDefault": settings.telestratorDefaults.enabledByDefault,
        },
        "decoderConfig": <String, Object?>{
          "enabledProfiles": settings.decoderConfig.enabledProfiles
              .map((DecoderProfile item) => item.name)
              .toList(),
        },
        "mdkLogVerbosity": settings.mdkLogVerbosity.name,
        "sceneSwitch": <String, Object?>{
          "obs": settings.obsSceneSwitchConfig == null
              ? null
              : <String, Object?>{
                  "serverAddress": settings.obsSceneSwitchConfig!.serverAddress,
                  "enabled": settings.obsSceneSwitchConfig!.enabled,
                  "port": settings.obsSceneSwitchConfig!.port,
                  "password": settings.obsSceneSwitchConfig!.password,
                  "videoScene": settings.obsSceneSwitchConfig!.videoScene,
                  "faceScene": settings.obsSceneSwitchConfig!.faceScene,
                },
          "webhooks": settings.webhookSceneSwitchConfigs
              .map(
                (WebhookSceneSwitchConfig item) => <String, Object?>{
                  "name": item.name,
                  "enabled": item.enabled,
                  "url": item.url,
                  "method": item.method.name.toUpperCase(),
                  "getQueryParamName": item.getQueryParamName,
                  "postBodyType": item.postBodyType.name,
                  "sceneKey": item.sceneKey,
                },
              )
              .toList(),
        },
        "ignoredFolders": settings.ignoredFolders,
      },
      "mediaItems": items.map((MediaListItem item) {
        final bool isClip = item.type == MediaListItemType.clip;
        return <String, Object?>{
          "identifier": isClip ? item.stableKey : item.fileName,
          "relativePath": p.relative(item.filePath, from: workspaceRoot),
          "tags": (tagsByItem[item.stableKey] ?? <String>{}).toList()..sort(),
          "clipRange": isClip
              ? <String, Object?>{
                  "inMs": item.clip!.inMs,
                  "outMs": item.clip!.outMs,
                }
              : null,
        };
      }).toList(),
    };
    await File(outputPath).writeAsString(
      const JsonEncoder.withIndent("  ").convert(payload),
    );
  }

  Future<void> _refreshTagsForItems(
    List<MediaListItem> items, {
    required bool refreshAllTags,
  }) async {
    final MediaRepository? repository = _mediaRepository;
    if (repository == null || items.isEmpty) {
      return;
    }
    final Map<String, Set<String>> tagsByItemKey = await repository.listTagsForItems(
      items,
    );
    for (final MediaListItem item in items) {
      _tagsByItemKey[item.stableKey] =
          tagsByItemKey[item.stableKey] ?? <String>{};
    }
    if (refreshAllTags) {
      _allTags
        ..clear()
        ..addAll(await repository.listAllTags());
    }
    _applyFilters();
    notifyListeners();
  }

  void _applyFilters() {
    final String fileNameSearch = _fileNameSearchQuery.trim().toLowerCase();
    final Set<String> requiredTags = _activeTagFilters
        .map((String tag) => tag.toLowerCase())
        .toSet();
    _visibleItems = _allItems.where((MediaListItem item) {
      final Set<String> tags = tagsForItem(item);
      final Set<String> userTags = tags.where(_isUserTag).toSet();
      final Set<String> tagsLower = tags
          .map((String tag) => tag.toLowerCase())
          .toSet();
      if (_showUntaggedOnly && userTags.isNotEmpty) {
        return false;
      }
      if (requiredTags.isNotEmpty && !requiredTags.every(tagsLower.contains)) {
        return false;
      }
      if (fileNameSearch.isNotEmpty &&
          !(_fileSearchUsesFullPath
              ? item.filePath.toLowerCase().contains(fileNameSearch)
              : item.fileName.toLowerCase().contains(fileNameSearch))) {
        return false;
      }
      return true;
    }).toList();
  }

  bool _isUserTag(String tag) =>
      tag != MediaRepository.masterTag && tag != MediaRepository.clipTag;

  @override
  void dispose() {
    unawaited(_mediaSubscription?.cancel());
    unawaited(_thumbnailSubscription?.cancel());
    unawaited(_ingestionService.dispose());
    super.dispose();
  }
}
