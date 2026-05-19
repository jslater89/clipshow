import "dart:async";
import "dart:convert";
import "dart:io";

import "package:file_picker/file_picker.dart";
import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:path/path.dart" as p;
import "package:system_fonts/system_fonts.dart";

import "package:obs_clipshow/src/data/app_database.dart";
import "package:obs_clipshow/src/data/media_repository.dart";
import "package:obs_clipshow/src/ingestion/ingestion_service.dart";
import "package:obs_clipshow/src/ingestion/thumbnail_service.dart";
import "package:obs_clipshow/src/ingestion/workspace_watcher.dart";
import "package:obs_clipshow/src/media/master_media_file.dart";
import "package:obs_clipshow/src/features/playout/playout_clip.dart";
import "package:obs_clipshow/src/media/media_list_item.dart";
import "package:obs_clipshow/src/obs/capture_path_utils.dart";
import "package:obs_clipshow/src/obs/playout_record_path_utils.dart";
import "package:obs_clipshow/src/osg/osg_models.dart";
import "package:obs_clipshow/src/obs/obs_capture_service.dart";
import "package:obs_clipshow/src/workspace/workspace_settings.dart";
import "package:obs_clipshow/src/workspace/workspace_preferences.dart";
import "package:obs_clipshow/src/util/system_trash.dart";
import "package:obs_clipshow/src/workspace/workspace_media_paths.dart";
import "package:obs_clipshow/src/workspace/workspace_service.dart";
import "package:obs_clipshow/src/workspace/workspace_trash.dart";

/// Manage (library prep) vs OBS Capture pane on the dashboard right column.
enum DashboardMediaPaneTab { manage, capture }

/// Result of stopping a Record playout session.
class PlayoutRecordStopResult {
  const PlayoutRecordStopResult({this.destPath, this.errorMessage});

  final String? destPath;
  final String? errorMessage;
}

bool _semanticTagAttachmentSnapshotsEqual(
  List<MediaTagAttachment> a,
  List<MediaTagAttachment> b,
) {
  final List<MediaTagAttachment> ca = List<MediaTagAttachment>.from(a);
  final List<MediaTagAttachment> cb = List<MediaTagAttachment>.from(b);
  ca.sort(
    (MediaTagAttachment p, MediaTagAttachment q) =>
        p.mediaTagId.compareTo(q.mediaTagId),
  );
  cb.sort(
    (MediaTagAttachment p, MediaTagAttachment q) =>
        p.mediaTagId.compareTo(q.mediaTagId),
  );
  if (ca.length != cb.length) {
    return false;
  }
  for (int i = 0; i < ca.length; i++) {
    final MediaTagAttachment x = ca[i];
    final MediaTagAttachment y = cb[i];
    if (x.mediaTagId != y.mediaTagId ||
        x.semanticTypeId != y.semanticTypeId ||
        x.tagName != y.tagName) {
      return false;
    }
  }
  return true;
}

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
  final Map<String, List<MediaTagAttachment>> _tagAttachmentsByItemKey =
      <String, List<MediaTagAttachment>>{};
  final Set<String> _activeTagFilters = <String>{};
  final List<String> _allTags = <String>[];
  final List<ShelfTagEntry> _savedTagEntries = <ShelfTagEntry>[];
  int _previewPositionMs = 0;
  int? _markInMs;
  int? _markOutMs;
  String _tagSearchQuery = "";
  String _fileNameSearchQuery = "";
  bool _fileSearchUsesFullPath = false;
  String? _selectedItemKey;
  bool _showUntaggedOnly = false;
  /// When set, [visibleItems] includes only clips whose [MediaClip.masterMediaId] matches.
  int? _clipsOfMasterFilterMediaId;
  WorkspaceSettingsBundle? _workspaceSettings;
  bool _dashboardPreviewPlaybackActive = false;
  DateTime? _previewPlayerInitNotBefore;
  DashboardMediaPaneTab _mediaPaneTab = DashboardMediaPaneTab.manage;
  final List<ShelfTagEntry> _captureTags = <ShelfTagEntry>[];
  bool _obsCaptureRecording = false;
  ObsCaptureService? _obsCaptureSession;
  String? _captureStatusMessage;
  bool _obsPlayoutRecordActive = false;
  ObsCaptureService? _obsPlayoutRecordSession;
  final Set<String> _loadedSystemFontFamilies = <String>{};

  OsgPresetVisibility _previewOsgPresetVisibility =
      const OsgPresetVisibility.allOff();
  int _previewOsgRequirementFlashToken = 0;
  String _previewOsgRequirementFlashText = "";

  /// Session-only clip volume (0.0–1.0), shared between preview and playout.
  /// Initialized once from [WorkspaceSettingsBundle.defaultClipVolume] on the
  /// first workspace settings load; user adjustments via hotkeys live only
  /// for the current app run.
  double _clipVolume = PlaybackVolumeDefaults.defaultVolume;
  bool _clipMuted = false;

  /// Volume at the moment [toggleClipMute] was called, so unmuting restores
  /// the exact prior level. Kept in sync with [_clipVolume] while unmuted.
  double _preMuteClipVolume = PlaybackVolumeDefaults.defaultVolume;
  bool _clipVolumeInitializedFromWorkspace = false;
  int _previewVolumeHudToken = 0;
  String _previewVolumeHudText = "";

  /// Bumps per [MediaListItem.stableKey] when that row’s tag attachments
  /// change in a way that affects OSG semantic resolution.
  final Map<String, int> _semanticTagSnapshotByItemKey = <String, int>{};

  bool get isLoading => _isLoading;
  String? get workspacePath => _workspacePath;
  List<MasterMediaFile> get mediaFiles => _mediaFiles;
  List<MediaListItem> get visibleItems => _visibleItems;
  List<String> get allTags => _allTags;
  List<ShelfTagEntry> get savedTags => _savedTagEntries;
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
      _fileNameSearchQuery.trim().isNotEmpty ||
      _clipsOfMasterFilterMediaId != null;

  int? get clipsOfMasterFilterMediaId => _clipsOfMasterFilterMediaId;

  bool get hasClipsOfMasterFilter => _clipsOfMasterFilterMediaId != null;

  String? get clipsOfMasterFilterChipLabel {
    final int? id = _clipsOfMasterFilterMediaId;
    if (id == null) {
      return null;
    }
    return "Clips of ${_displayNameForMasterMediaId(id)}";
  }
  bool get showUntaggedOnly => _showUntaggedOnly;
  String? get selectedItemKey => _selectedItemKey;
  TelestratorDefaults get telestratorDefaults =>
      _workspaceSettings?.telestratorDefaults ?? TelestratorDefaults.fallback();
  DecoderConfig get decoderConfig =>
      _workspaceSettings?.decoderConfig ?? DecoderConfig.platformFallback();
  MdkLogVerbosity get mdkLogVerbosity =>
      _workspaceSettings?.mdkLogVerbosity ?? MdkLogVerbosity.warning;

  FvpLogVerbosity get fvpLogVerbosity =>
      _workspaceSettings?.fvpLogVerbosity ?? FvpLogVerbosity.warning;
  ObsSceneSwitchConfig? get obsSceneSwitchConfig =>
      _workspaceSettings?.obsSceneSwitchConfig;
  List<WebhookSceneSwitchConfig> get webhookSceneSwitchConfigs =>
      _workspaceSettings?.webhookSceneSwitchConfigs ??
      <WebhookSceneSwitchConfig>[];
  List<String> get ignoredFolders =>
      _workspaceSettings?.ignoredFolders ?? <String>[];
  DashboardMediaPaneTab get mediaPaneTab => _mediaPaneTab;
  CapturePathsSettings get capturePathsSettings =>
      _workspaceSettings?.capturePathsSettings ??
      CapturePathsSettings.fallback();
  PlayoutRecordPathsSettings get playoutRecordPathsSettings =>
      _workspaceSettings?.playoutRecordPathsSettings ??
      PlayoutRecordPathsSettings.fallback();
  bool get obsPlayoutRecordActive => _obsPlayoutRecordActive;
  bool get pauseIngestScanDuringPreview =>
      _workspaceSettings?.pauseIngestScanDuringPreview ?? true;

  int get ingestProbeConcurrency =>
      _workspaceSettings?.ingestProbeConcurrency ??
      IngestionConcurrencyDefaults.probeDefault;

  int get ingestThumbnailConcurrency =>
      _workspaceSettings?.ingestThumbnailConcurrency ??
      IngestionConcurrencyDefaults.thumbnailDefault;

  PlayoutOutputSize get playoutOutputSize =>
      _workspaceSettings?.playoutOutputSize ?? PlayoutOutputSize.fallback;

  OsgWorkspaceConfig get osgWorkspaceConfig =>
      _workspaceSettings?.osgWorkspaceConfig ?? OsgWorkspaceConfig.fallback();

  List<TagSemanticType> get tagSemanticTypes =>
      _workspaceSettings?.tagSemanticTypes ?? <TagSemanticType>[];
  List<ShelfTagEntry> get captureTags =>
      List<ShelfTagEntry>.unmodifiable(_captureTags);
  bool get obsCaptureRecording => _obsCaptureRecording;
  String? get captureStatusMessage => _captureStatusMessage;

  /// Visibilities for OSG presets in the dashboard preview (mirrors playout 6–0).
  OsgPresetVisibility get previewOsgPresetVisibility => _previewOsgPresetVisibility;

  int get previewOsgRequirementFlashToken => _previewOsgRequirementFlashToken;

  String get previewOsgRequirementFlashText => _previewOsgRequirementFlashText;

  void clearPreviewOsgRequirementFlash() {
    if (_previewOsgRequirementFlashToken == 0) {
      return;
    }
    _previewOsgRequirementFlashToken = 0;
    _previewOsgRequirementFlashText = "";
    notifyListeners();
  }

  void _flashPreviewOsgRequirementMessage(String text) {
    _previewOsgRequirementFlashText = text;
    _previewOsgRequirementFlashToken++;
    notifyListeners();
  }

  /// Volume currently configured for clip playback (preview + playout).
  /// This is the user's intended level; if [clipMuted] is true the audible
  /// value is 0 (see [effectiveClipVolume]).
  double get clipVolume => _clipVolume;

  bool get clipMuted => _clipMuted;

  /// Volume passed to [ClipPlayerView] — zero when muted.
  double get effectiveClipVolume => _clipMuted ? 0.0 : _clipVolume;

  double get defaultClipVolume =>
      _workspaceSettings?.defaultClipVolume ??
      PlaybackVolumeDefaults.defaultVolume;

  int get previewVolumeHudToken => _previewVolumeHudToken;

  String get previewVolumeHudText => _previewVolumeHudText;

  void clearPreviewVolumeHud() {
    if (_previewVolumeHudToken == 0) {
      return;
    }
    _previewVolumeHudToken = 0;
    _previewVolumeHudText = "";
    notifyListeners();
  }

  void _flashPreviewVolumeHud(String text) {
    _previewVolumeHudText = text;
    _previewVolumeHudToken++;
  }

  String _formatVolumePercent(double value) {
    return "Volume ${(PlaybackVolumeDefaults.clamp(value) * 100).round()}%";
  }

  /// Nudge the shared session clip volume by [delta] (positive or negative,
  /// typically [PlaybackVolumeDefaults.step]). Unmutes if currently muted.
  void nudgeClipVolume(double delta) {
    final double next = PlaybackVolumeDefaults.clamp(_clipVolume + delta);
    final bool changedVolume = next != _clipVolume;
    final bool wasMuted = _clipMuted;
    _clipVolume = next;
    _preMuteClipVolume = next;
    if (wasMuted) {
      _clipMuted = false;
    }
    if (!changedVolume && !wasMuted) {
      _flashPreviewVolumeHud(_formatVolumePercent(_clipVolume));
      notifyListeners();
      return;
    }
    _flashPreviewVolumeHud(_formatVolumePercent(_clipVolume));
    notifyListeners();
  }

  /// Toggle mute on the shared clip volume. Unmuting restores the level that
  /// was active when mute was engaged.
  void toggleClipMute() {
    if (_clipMuted) {
      _clipMuted = false;
      _clipVolume = _preMuteClipVolume;
      _flashPreviewVolumeHud(_formatVolumePercent(_clipVolume));
    } else {
      _preMuteClipVolume = _clipVolume;
      _clipMuted = true;
      _flashPreviewVolumeHud("Muted");
    }
    notifyListeners();
  }

  Set<int> semanticTypeIdsOnMedia(MediaListItem item) {
    final List<MediaTagAttachment> list = tagAttachmentsForItem(item);
    return <int>{
      for (final MediaTagAttachment a in list)
        if (a.semanticTypeId != null) a.semanticTypeId!,
    };
  }

  void _reconcilePreviewOsgPresetVisibilityForSelectedItem() {
    final MediaListItem? item = selectedItem;
    if (item == null) {
      _previewOsgPresetVisibility = const OsgPresetVisibility.allOff();
      return;
    }
    final Set<int> onMedia = semanticTypeIdsOnMedia(item);
    final List<OsgPreset> presets = osgWorkspaceConfig.workspacePresets;
    OsgPresetVisibility next = _previewOsgPresetVisibility;
    for (final OsgPresetSlot slot in OsgPresetSlot.values) {
      if (!next[slot]) {
        continue;
      }
      final OsgPreset p = presets[slot.presetIndex];
      if (!p.enabled) {
        next = next.withSlot(slot, false);
        continue;
      }
      if (p.requiredSemanticTypeIds.isNotEmpty &&
          !p.semanticRequirementsSatisfiedBy(onMedia)) {
        next = next.withSlot(slot, false);
      }
    }
    _previewOsgPresetVisibility = next;
  }

  void togglePreviewOsgPresetSlot(OsgPresetSlot slot) {
    final int index = slot.presetIndex;
    if (index < 0 || index >= OsgPresetSlot.values.length) {
      return;
    }
    final OsgPreset preset = osgWorkspaceConfig.workspacePresets[index];
    if (!preset.enabled) {
      return;
    }
    final bool next = !_previewOsgPresetVisibility[slot];
    if (next) {
      if (preset.requiredSemanticTypeIds.isNotEmpty) {
        final MediaListItem? item = selectedItem;
        if (item == null) {
          return;
        }
        final Set<int> onMedia = semanticTypeIdsOnMedia(item);
        if (!preset.semanticRequirementsSatisfiedBy(onMedia)) {
          _flashPreviewOsgRequirementMessage(
            osgMissingSemanticRequirementsMessage(
              preset: preset,
              semanticTypeIdsOnMedia: onMedia,
              tagSemanticTypes: tagSemanticTypes,
            ),
          );
          return;
        }
      }
    }
    _previewOsgPresetVisibility =
        _previewOsgPresetVisibility.withSlot(slot, next);
    notifyListeners();
  }

  int semanticTagSnapshotForItem(MediaListItem item) =>
      _semanticTagSnapshotByItemKey[item.stableKey] ?? 0;

  void setMediaPaneTab(DashboardMediaPaneTab tab) {
    if (_mediaPaneTab == tab) {
      return;
    }
    _mediaPaneTab = tab;
    notifyListeners();
  }

  void setCaptureTags(List<ShelfTagEntry> tags) {
    _captureTags
      ..clear()
      ..addAll(tags);
    notifyListeners();
  }

  void addCaptureTag(String raw, {int? semanticTypeId}) {
    final MediaRepository? repository = _mediaRepository;
    if (repository == null) {
      return;
    }
    final String normalized = repository.normalizeTag(raw);
    if (normalized.isEmpty) {
      return;
    }
    final int idx = _captureTags.indexWhere(
      (ShelfTagEntry e) => e.name.toLowerCase() == normalized.toLowerCase(),
    );
    if (idx >= 0) {
      if (semanticTypeId == null) {
        return;
      }
      final ShelfTagEntry existing = _captureTags[idx];
      _captureTags[idx] = ShelfTagEntry(
        name: existing.name,
        semanticTypeId: semanticTypeId,
      );
      notifyListeners();
      return;
    }
    _captureTags.add(
      ShelfTagEntry(name: normalized, semanticTypeId: semanticTypeId),
    );
    notifyListeners();
  }

  void removeCaptureTag(String tag) {
    _captureTags.removeWhere(
      (ShelfTagEntry e) => e.name.toLowerCase() == tag.toLowerCase(),
    );
    notifyListeners();
  }

  void setCaptureTagSemanticType({
    required String tagName,
    int? semanticTypeId,
  }) {
    final MediaRepository? repository = _mediaRepository;
    if (repository == null) {
      return;
    }
    final String normalized = repository.normalizeTag(tagName);
    if (normalized.isEmpty) {
      return;
    }
    final int idx = _captureTags.indexWhere(
      (ShelfTagEntry e) => e.name.toLowerCase() == normalized.toLowerCase(),
    );
    if (idx < 0) {
      return;
    }
    final ShelfTagEntry existing = _captureTags[idx];
    _captureTags[idx] = ShelfTagEntry(
      name: existing.name,
      semanticTypeId: semanticTypeId,
    );
    notifyListeners();
  }

  /// Items that would receive at least one saved tag via [applyAllSavedTagsToItems].
  List<MediaListItem> _itemsNeedingSavedTagApply({
    required bool filteredOnly,
  }) {
    final MediaRepository? repository = _mediaRepository;
    if (repository == null || _savedTagEntries.isEmpty) {
      return <MediaListItem>[];
    }
    final List<MediaListItem> targetItems = List<MediaListItem>.from(
      filteredOnly ? _visibleItems : _allItems,
    );
    final List<ShelfTagEntry> saved = List<ShelfTagEntry>.from(_savedTagEntries);
    if (targetItems.isEmpty) {
      return <MediaListItem>[];
    }
    final List<String> savedNamesLower = saved
        .map((ShelfTagEntry e) => e.name.toLowerCase())
        .toList();
    final List<MediaListItem> itemsNeedingUpdate = <MediaListItem>[];
    for (final MediaListItem item in targetItems) {
      final Set<String> existingTagsLower =
          (_tagsByItemKey[item.stableKey] ?? <String>{})
              .map((String tag) => tag.toLowerCase())
              .toSet();
      final bool needsUpdate = savedNamesLower.any(
        (String nameLower) => !existingTagsLower.contains(nameLower),
      );
      if (needsUpdate) {
        itemsNeedingUpdate.add(item);
      }
    }
    return itemsNeedingUpdate;
  }

  int countItemsNeedingSavedTagsApply({required bool filteredOnly}) =>
      _itemsNeedingSavedTagApply(filteredOnly: filteredOnly).length;

  void mergeSavedTagsIntoCapture() {
    for (final ShelfTagEntry e in _savedTagEntries) {
      addCaptureTag(e.name, semanticTypeId: e.semanticTypeId);
    }
    setMediaPaneTab(DashboardMediaPaneTab.capture);
  }

  void mergeSelectedItemTagsIntoCapture() {
    final MediaListItem? item = selectedItem;
    if (item == null) {
      return;
    }
    for (final MediaTagAttachment att in tagAttachmentsForItem(item)) {
      if (!_isUserTag(att.tagName)) {
        continue;
      }
      addCaptureTag(att.tagName, semanticTypeId: att.semanticTypeId);
    }
    setMediaPaneTab(DashboardMediaPaneTab.capture);
  }

  Future<void> saveCapturePathsSettings(CapturePathsSettings value) async {
    final MediaRepository? repository = _mediaRepository;
    if (repository == null) {
      return;
    }
    await repository.saveCapturePathsSettings(value);
    await _ingestionService.refreshIgnoredFolders();
    await _loadWorkspaceSettings();
    notifyListeners();
  }

  Future<void> savePlayoutRecordPathsSettings(
    PlayoutRecordPathsSettings value,
  ) async {
    final MediaRepository? repository = _mediaRepository;
    if (repository == null) {
      return;
    }
    await repository.savePlayoutRecordPathsSettings(value);
    await _ingestionService.refreshIgnoredFolders();
    await _loadWorkspaceSettings();
    notifyListeners();
  }

  /// Persists capture and playout record paths after validation.
  ///
  /// Returns an error message when validation fails; null on success.
  Future<String?> saveObsPathsSettings({
    required CapturePathsSettings capture,
    required PlayoutRecordPathsSettings playoutRecord,
  }) async {
    final String? workspaceRoot = _workspacePath;
    if (workspaceRoot == null) {
      return "No workspace open.";
    }
    final String captureRec = CapturePathUtils.normalizedRecordingDir(
      workspaceAbsolute: workspaceRoot,
      settings: capture,
    );
    final String captureOut = CapturePathUtils.normalizedOutputDir(
      workspaceAbsolute: workspaceRoot,
      settings: capture,
    );
    if (CapturePathUtils.isOutputInsideRecordingTree(
      recordingDirAbsolute: captureRec,
      outputDirAbsolute: captureOut,
    )) {
      return "Capture output folder cannot be inside the capture recording folder.";
    }
    final String playoutStaging = PlayoutRecordPathUtils.normalizedStagingDir(
      workspaceAbsolute: workspaceRoot,
      settings: playoutRecord,
    );
    final String playoutOut = PlayoutRecordPathUtils.normalizedOutputDir(
      workspaceAbsolute: workspaceRoot,
      settings: playoutRecord,
    );
    if (PlayoutRecordPathUtils.isOutputInsideStagingTree(
      stagingDirAbsolute: playoutStaging,
      outputDirAbsolute: playoutOut,
    )) {
      return "Playout output folder cannot be inside the playout record staging folder.";
    }
    await saveCapturePathsSettings(capture);
    await savePlayoutRecordPathsSettings(playoutRecord);
    return null;
  }

  /// Starts OBS recording for the current playout session.
  ///
  /// Returns null on success, or a user-facing error message.
  Future<String?> startPlayoutRecord() async {
    final String? workspaceRoot = _workspacePath;
    final ObsSceneSwitchConfig? obsCfg = obsSceneSwitchConfig;
    if (workspaceRoot == null) {
      return "No workspace open.";
    }
    if (obsCfg == null || !obsCfg.enabled) {
      return "Enable OBS in Workspace Settings.";
    }
    if (_obsCaptureSession != null || _obsCaptureRecording) {
      return "Stop Capture mode recording before Record playout.";
    }
    if (_obsPlayoutRecordSession != null || _obsPlayoutRecordActive) {
      return "A playout record session is already active.";
    }
    final ObsCaptureService service = ObsCaptureService(
      url: "ws://${obsCfg.serverAddress}:${obsCfg.port}",
      password: obsCfg.password.isEmpty ? null : obsCfg.password,
    );
    _obsPlayoutRecordSession = service;
    _obsPlayoutRecordActive = true;
    notifyListeners();
    try {
      if (await service.isObsRecordActive()) {
        await service.restoreObsRecordDirectoryAndClose();
        _obsPlayoutRecordSession = null;
        _obsPlayoutRecordActive = false;
        notifyListeners();
        return "OBS is already recording. Stop recording in OBS first.";
      }
      final PlayoutRecordPathsSettings paths = playoutRecordPathsSettings;
      final String stagingAbs = PlayoutRecordPathUtils.normalizedStagingDir(
        workspaceAbsolute: workspaceRoot,
        settings: paths,
      );
      await service.startPlayoutRecording(stagingAbsolute: stagingAbs);
      return null;
    } catch (e, st) {
      _logger.warning("startPlayoutRecord failed: $e\n$st");
      await service.restoreObsRecordDirectoryAndClose();
      _obsPlayoutRecordSession = null;
      _obsPlayoutRecordActive = false;
      notifyListeners();
      return "Failed to start recording: $e";
    }
  }

  /// Stops playout recording, copies to the configured output folder, restores OBS.
  Future<PlayoutRecordStopResult> stopPlayoutRecordAndCopy() async {
    final String? workspaceRoot = _workspacePath;
    final ObsCaptureService? service = _obsPlayoutRecordSession;
    if (workspaceRoot == null || service == null) {
      return const PlayoutRecordStopResult(
        errorMessage: "No playout recording to stop.",
      );
    }
    final PlayoutRecordPathsSettings paths = playoutRecordPathsSettings;
    String? destPath;
    try {
      final String? stagingPath = await service.stopRecordingStagingPath();
      if (stagingPath == null) {
        return const PlayoutRecordStopResult(
          errorMessage: "Could not resolve recorded file path from OBS.",
        );
      }
      final String outputDirAbs = PlayoutRecordPathUtils.normalizedOutputDir(
        workspaceAbsolute: workspaceRoot,
        settings: paths,
      );
      destPath = await copyCaptureToOutputDir(
        stagingFileAbsolute: stagingPath,
        outputDirAbsolute: outputDirAbs,
      );
      return PlayoutRecordStopResult(destPath: destPath);
    } catch (e, st) {
      _logger.warning("stopPlayoutRecordAndCopy failed: $e\n$st");
      return PlayoutRecordStopResult(errorMessage: "Record export failed: $e");
    } finally {
      await service.restoreObsRecordDirectoryAndClose();
      _obsPlayoutRecordSession = null;
      _obsPlayoutRecordActive = false;
      notifyListeners();
    }
  }

  Future<void> startObsCapture() async {
    final MediaRepository? repository = _mediaRepository;
    final String? workspaceRoot = _workspacePath;
    final ObsSceneSwitchConfig? obsCfg = obsSceneSwitchConfig;
    if (repository == null || workspaceRoot == null) {
      _captureStatusMessage = "No workspace.";
      notifyListeners();
      return;
    }
    if (_obsCaptureSession != null || _obsCaptureRecording) {
      _captureStatusMessage = "A capture session is already active.";
      notifyListeners();
      return;
    }
    if (obsCfg == null || !obsCfg.enabled) {
      _captureStatusMessage = "Enable OBS in Workspace Settings.";
      notifyListeners();
      return;
    }
    final CapturePathsSettings paths = capturePathsSettings;
    final String recordingAbs = CapturePathUtils.normalizedRecordingDir(
      workspaceAbsolute: workspaceRoot,
      settings: paths,
    );
    final String outputAbs = CapturePathUtils.normalizedOutputDir(
      workspaceAbsolute: workspaceRoot,
      settings: paths,
    );
    if (CapturePathUtils.isOutputInsideRecordingTree(
      recordingDirAbsolute: recordingAbs,
      outputDirAbsolute: outputAbs,
    )) {
      _captureStatusMessage =
          "Output folder cannot be inside the recording folder. Adjust Capture paths in settings.";
      notifyListeners();
      return;
    }
    _captureStatusMessage = null;
    final ObsCaptureService service = ObsCaptureService(
      url: "ws://${obsCfg.serverAddress}:${obsCfg.port}",
      password: obsCfg.password.isEmpty ? null : obsCfg.password,
    );
    _obsCaptureSession = service;
    _obsCaptureRecording = true;
    notifyListeners();
    try {
      await service.startRecording(
        workspaceAbsolute: workspaceRoot,
        paths: paths,
        captureSceneName: obsCfg.captureScene.trim().isEmpty
            ? null
            : obsCfg.captureScene,
      );
      _captureStatusMessage = "Recording…";
    } catch (e, st) {
      _logger.warning("startObsCapture failed: $e\n$st");
      _captureStatusMessage = "Failed to start recording: $e";
      await service.restoreObsRecordDirectoryAndClose();
      _obsCaptureSession = null;
    } finally {
      _obsCaptureRecording = _obsCaptureSession != null;
      notifyListeners();
    }
  }

  Future<void> stopObsCaptureAndIngestTags() async {
    final MediaRepository? repository = _mediaRepository;
    final String? workspaceRoot = _workspacePath;
    final ObsCaptureService? service = _obsCaptureSession;
    if (repository == null || workspaceRoot == null || service == null) {
      _captureStatusMessage = "Nothing to stop.";
      notifyListeners();
      return;
    }
    final List<ShelfTagEntry> tagSnapshot = List<ShelfTagEntry>.from(
      _captureTags,
    );
    final CapturePathsSettings paths = capturePathsSettings;
    _captureStatusMessage = "Stopping…";
    notifyListeners();
    String? stagingPath;
    String? destPath;
    try {
      stagingPath = await service.stopRecordingStagingPath();
      if (stagingPath == null) {
        _captureStatusMessage =
            "Could not resolve recorded file path from OBS.";
        return;
      }
      final String outputDirAbs = CapturePathUtils.normalizedOutputDir(
        workspaceAbsolute: workspaceRoot,
        settings: paths,
      );
      _captureStatusMessage = "Finalizing recording on disk…";
      notifyListeners();
      destPath = await copyCaptureToOutputDir(
        stagingFileAbsolute: stagingPath,
        outputDirAbsolute: outputDirAbs,
      );
      _captureStatusMessage = "Waiting for ingest…";
      notifyListeners();
      final MasterMediaFile? master = await _waitForMasterAtPath(
        repository,
        destPath,
      );
      if (master == null) {
        _captureStatusMessage =
            "Copied to ${p.basename(destPath)}, but ingest did not pick it up in time.";
        return;
      }
      for (final ShelfTagEntry e in tagSnapshot) {
        await repository.addTagToMedia(
          mediaType: MediaListItemType.master,
          mediaId: master.id,
          tag: e.name,
          semanticTypeId: e.semanticTypeId,
        );
      }
      await _reloadFromRepository();
      _captureStatusMessage =
          "Saved ${p.basename(destPath)} with ${tagSnapshot.length} tag(s).";
    } catch (e, st) {
      _logger.warning("stopObsCapture failed: $e\n$st");
      _captureStatusMessage = "Capture failed: $e";
    } finally {
      await service.restoreObsRecordDirectoryAndClose();
      _obsCaptureSession = null;
      _obsCaptureRecording = false;
      notifyListeners();
    }
  }

  Future<MasterMediaFile?> _waitForMasterAtPath(
    MediaRepository repository,
    String absolutePath,
  ) async {
    final String? workspaceRoot = _workspacePath;
    if (workspaceRoot == null) {
      return null;
    }
    final String normalized = p.normalize(absolutePath);
    const Duration step = Duration(milliseconds: 400);
    for (int i = 0; i < 150; i++) {
      final MasterMediaFile? master = await repository.getMasterByFilePath(
        normalized,
        workspaceRoot,
      );
      if (master != null) {
        return master;
      }
      await Future<void>.delayed(step);
    }
    return null;
  }

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

  List<MediaTagAttachment> tagAttachmentsForItem(MediaListItem item) =>
      _tagAttachmentsByItemKey[item.stableKey] ?? <MediaTagAttachment>[];

  Future<String?> resolveSemanticTagText(
    PlayoutClip clip,
    int semanticTypeId,
  ) async {
    final MediaRepository? repository = _mediaRepository;
    if (repository == null) {
      return null;
    }
    return repository.resolveSemanticTagForMedia(
      mediaType: clip.mediaType,
      mediaId: clip.mediaId,
      semanticTypeId: semanticTypeId,
    );
  }

  Future<void> savePlayoutOutputSize(PlayoutOutputSize value) async {
    final MediaRepository? repository = _mediaRepository;
    if (repository == null) {
      return;
    }
    await repository.savePlayoutOutputSize(value);
    await _loadWorkspaceSettings();
    notifyListeners();
  }

  Future<void> saveOsgWorkspaceConfig(OsgWorkspaceConfig value) async {
    final MediaRepository? repository = _mediaRepository;
    if (repository == null) {
      return;
    }
    await repository.saveOsgWorkspaceConfig(value);
    await _loadWorkspaceSettings();
    await _preloadConfiguredOsgFonts();
    notifyListeners();
  }

  Future<int> insertTagSemanticType({
    required String name,
    int? iconCodePoint,
  }) async {
    final MediaRepository? repository = _mediaRepository;
    if (repository == null) {
      return -1;
    }
    final int id = await repository.insertTagSemanticType(
      name: name,
      iconCodePoint: iconCodePoint,
    );
    await _loadWorkspaceSettings();
    notifyListeners();
    return id;
  }

  Future<void> updateTagSemanticType({
    required int id,
    required String name,
    int? iconCodePoint,
  }) async {
    final MediaRepository? repository = _mediaRepository;
    if (repository == null) {
      return;
    }
    await repository.updateTagSemanticType(
      id: id,
      name: name,
      iconCodePoint: iconCodePoint,
    );
    await _loadWorkspaceSettings();
    notifyListeners();
  }

  Future<bool> deleteTagSemanticType(int id) async {
    final MediaRepository? repository = _mediaRepository;
    if (repository == null) {
      return false;
    }
    final bool ok = await repository.deleteTagSemanticType(id);
    if (ok) {
      await _loadWorkspaceSettings();
      await _reloadFromRepository();
      notifyListeners();
    }
    return ok;
  }

  Future<void> setMediaTagSemanticType({
    required int mediaTagId,
    int? semanticTypeId,
  }) async {
    final MediaRepository? repository = _mediaRepository;
    if (repository == null) {
      return;
    }
    await repository.setMediaTagSemanticType(
      mediaTagId: mediaTagId,
      semanticTypeId: semanticTypeId,
    );
    await _reloadFromRepository();
  }

  Future<void> swapTagValueOnMediaTag({
    required int mediaTagId,
    required String newTagName,
  }) async {
    final MediaRepository? repository = _mediaRepository;
    if (repository == null) {
      return;
    }
    await repository.swapTagValueOnMediaTag(
      mediaTagId: mediaTagId,
      newTagName: newTagName,
    );
    await _reloadFromRepository();
  }

  Future<void> bulkSetSemanticTypeForTagId({
    required int tagId,
    int? semanticTypeId,
  }) async {
    final MediaRepository? repository = _mediaRepository;
    if (repository == null) {
      return;
    }
    await repository.bulkSetSemanticTypeForTagId(
      tagId: tagId,
      semanticTypeId: semanticTypeId,
    );
    await _reloadFromRepository();
  }

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

  List<String> searchTagSuggestionsFor(String query) {
    final String normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return _allTags.take(20).toList();
    }
    return _allTags
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
    _clipsOfMasterFilterMediaId = null;
    _previewOsgPresetVisibility = const OsgPresetVisibility.allOff();
    _semanticTagSnapshotByItemKey.clear();
    _mediaRepository = session.mediaRepository;
    _workspacePath = session.workspace.rootPath;
    await _loadWorkspaceSettings();
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
    await _preloadConfiguredOsgFonts();
    await _reloadFromRepository();
  }

  Future<void> _preloadConfiguredOsgFonts() async {
    final WorkspaceSettingsBundle? settings = _workspaceSettings;
    if (settings == null) {
      return;
    }
    final Set<String> configuredFamilies = <String>{};
    for (final OsgPreset preset in settings.osgWorkspaceConfig.workspacePresets) {
      for (final OsgSlot slot in preset.slots) {
        final String? family = slot.fontFamily?.trim();
        if (family == null || family.isEmpty) {
          continue;
        }
        configuredFamilies.add(family);
      }
    }
    for (final String family in configuredFamilies) {
      if (_loadedSystemFontFamilies.contains(family)) {
        continue;
      }
      try {
        await SystemFonts().loadFont(family);
        _loadedSystemFontFamilies.add(family);
      } catch (e, st) {
        _logger.fine("Failed to preload system font '$family': $e\n$st");
      }
    }
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
    _reconcilePreviewOsgPresetVisibilityForSelectedItem();
    notifyListeners();
  }

  void selectMasterForClip(MediaListItem clipItem) {
    if (clipItem.type != MediaListItemType.clip) {
      return;
    }
    final int masterId = clipItem.clip!.masterMediaId;
    for (final MediaListItem item in _allItems) {
      if (item.type == MediaListItemType.master && item.id == masterId) {
        selectItem(item);
        return;
      }
    }
  }

  int clipCountForMaster(int masterMediaId) {
    int n = 0;
    for (final MediaListItem item in _allItems) {
      if (item.type == MediaListItemType.clip &&
          item.clip!.masterMediaId == masterMediaId) {
        n++;
      }
    }
    return n;
  }

  void toggleClipsOfMasterFilter(int masterMediaId) {
    if (_clipsOfMasterFilterMediaId == masterMediaId) {
      _clipsOfMasterFilterMediaId = null;
    } else {
      _clipsOfMasterFilterMediaId = masterMediaId;
    }
    _applyFilters();
    notifyListeners();
  }

  void clearClipsOfMasterFilter() {
    if (_clipsOfMasterFilterMediaId == null) {
      return;
    }
    _clipsOfMasterFilterMediaId = null;
    _applyFilters();
    notifyListeners();
  }

  String _displayNameForMasterMediaId(int masterMediaId) {
    for (final MediaListItem item in _allItems) {
      if (item.type == MediaListItemType.master &&
          item.master!.id == masterMediaId) {
        return item.displayName;
      }
    }
    return "Master #$masterMediaId";
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

  Future<void> addSavedTag(String tag, {int? semanticTypeId}) async {
    final MediaRepository? repository = _mediaRepository;
    if (repository == null) {
      return;
    }
    await repository.addSavedTag(tag, semanticTypeId: semanticTypeId);
    await _reloadFromRepository();
  }

  Future<void> setSavedTagSemanticType({
    required String tagName,
    int? semanticTypeId,
  }) async {
    final MediaRepository? repository = _mediaRepository;
    if (repository == null) {
      return;
    }
    await repository.setSavedTagSemanticType(
      tag: tagName,
      semanticTypeId: semanticTypeId,
    );
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

  Future<void> renameSavedTagOnShelf({
    required String oldName,
    required String newName,
  }) async {
    final MediaRepository? repository = _mediaRepository;
    if (repository == null) {
      return;
    }
    await repository.renameSavedTag(oldName: oldName, newName: newName);
    renameCaptureTagEntry(oldName: oldName, newName: newName);
    await _reloadFromRepository();
  }

  void renameCaptureTagEntry({
    required String oldName,
    required String newName,
  }) {
    final MediaRepository? repository = _mediaRepository;
    if (repository == null) {
      return;
    }
    final String o = repository.normalizeTag(oldName);
    final String n = repository.normalizeTag(newName);
    if (o.isEmpty || n.isEmpty || o.toLowerCase() == n.toLowerCase()) {
      return;
    }
    final int idxOld = _captureTags.indexWhere(
      (ShelfTagEntry e) => e.name.toLowerCase() == o.toLowerCase(),
    );
    if (idxOld < 0) {
      return;
    }
    final int? sem = _captureTags[idxOld].semanticTypeId;
    _captureTags.removeAt(idxOld);
    final int idxNew = _captureTags.indexWhere(
      (ShelfTagEntry e) => e.name.toLowerCase() == n.toLowerCase(),
    );
    if (idxNew >= 0) {
      final ShelfTagEntry exist = _captureTags[idxNew];
      _captureTags[idxNew] = ShelfTagEntry(
        name: exist.name,
        semanticTypeId: sem ?? exist.semanticTypeId,
      );
    } else {
      _captureTags.add(ShelfTagEntry(name: n, semanticTypeId: sem));
    }
    notifyListeners();
  }

  Future<int?> lookupTagIdForLibraryTagName(String tagName) async {
    final MediaRepository? repository = _mediaRepository;
    if (repository == null) {
      return null;
    }
    return repository.lookupTagIdByNormalizedName(tagName);
  }

  Future<void> setDisplayNameOverride(
    MediaListItem item,
    String? override,
  ) async {
    final MediaRepository? repository = _mediaRepository;
    if (repository == null) {
      return;
    }
    await repository.setDisplayNameOverride(
      mediaType: item.type,
      mediaId: item.id,
      displayNameOverride: override,
    );
    await _reloadFromRepository();
  }

  Future<void> setAnnotations(
    MediaListItem item,
    String? annotations,
  ) async {
    final MediaRepository? repository = _mediaRepository;
    if (repository == null) {
      return;
    }
    await repository.setMediaAnnotations(
      mediaType: item.type,
      mediaId: item.id,
      annotations: annotations,
    );
    await _reloadFromRepository();
  }

  Future<void> applySavedTagToSelectedMedia(String tag) async {
    await addTagToSelectedMedia(tag);
  }

  Future<void> applyAllSavedTagsToSelectedMedia() async {
    final MediaListItem? item = selectedItem;
    final MediaRepository? repository = _mediaRepository;
    if (item == null || repository == null || _savedTagEntries.isEmpty) {
      return;
    }
    for (final ShelfTagEntry e in _savedTagEntries) {
      await repository.addTagToMedia(
        mediaType: item.type,
        mediaId: item.id,
        tag: e.name,
        semanticTypeId: e.semanticTypeId,
      );
    }
    await _reloadFromRepository();
  }

  Future<int> applyAllSavedTagsToItems({required bool filteredOnly}) async {
    final MediaRepository? repository = _mediaRepository;
    if (repository == null || _savedTagEntries.isEmpty) {
      return 0;
    }
    final List<ShelfTagEntry> savedTags = List<ShelfTagEntry>.from(
      _savedTagEntries,
    );
    final List<MediaListItem> itemsNeedingUpdate = _itemsNeedingSavedTagApply(
      filteredOnly: filteredOnly,
    );
    if (itemsNeedingUpdate.isEmpty) {
      return 0;
    }
    for (
      int i = 0;
      i < itemsNeedingUpdate.length;
      i += _savedTagApplyBatchSize
    ) {
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
    // [_refreshTagsForItems] skips the attachment diff in [_reloadFromRepository], so
    // bump snapshots so preview/playout OSG layers reload semantic tag text.
    for (final MediaListItem item in itemsNeedingUpdate) {
      final String k = item.stableKey;
      _semanticTagSnapshotByItemKey[k] =
          (_semanticTagSnapshotByItemKey[k] ?? 0) + 1;
    }
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

  /// Sends the master video to the **system** trash when possible; otherwise moves
  /// it to [WorkspaceTrash.relativeFolder] under the workspace. Then removes its
  /// DB row (clips referencing this master are removed via FK cascade and tag
  /// cleanup in [MediaRepository.deleteByPath]) and syncs ingestion snapshot.
  Future<String?> trashSelectedMasterFile() async {
    final MediaRepository? repository = _mediaRepository;
    final MasterMediaFile? master = selectedMedia;
    final String? workspaceRoot = _workspacePath;
    if (repository == null || master == null || workspaceRoot == null) {
      return "Select a master file first.";
    }
    final String storedPath = master.filePath;
    final String sourcePath = WorkspaceMediaPaths.absoluteMasterPath(
      workspaceRoot,
      storedPath,
    );
    final File sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      return "File not found on disk.";
    }
    try {
      await moveFileToSystemTrash(sourcePath);
    } catch (e, st) {
      _logger.warning(
        "System trash failed; falling back to workspace trash: $e\n$st",
      );
      try {
        await repository.addIgnoredFolder(WorkspaceTrash.relativeFolder);
        await _ingestionService.refreshIgnoredFolders();
        await moveFileToWorkspaceTrash(
          absoluteSourcePath: sourcePath,
          workspaceRoot: workspaceRoot,
        );
      } catch (e2, st2) {
        _logger.warning("Workspace trash fallback failed: $e2\n$st2");
        return "Could not move file to trash: $e2";
      }
    }
    await repository.deleteByPath(storedPath);
    await _ingestionService.removeMasterFromSnapshotAfterDbDelete(storedPath);
    await _reloadFromRepository();
    return null;
  }

  Future<void> nudgeSelectedClipStart(int deltaMs) async {
    final MediaRepository? repository = _mediaRepository;
    final MediaListItem? item = selectedItem;
    if (repository == null ||
        item == null ||
        item.type != MediaListItemType.clip) {
      return;
    }
    final int currentIn = item.clip!.inMs;
    final int? currentOut = item.clip!.outMs;
    int nextIn = currentIn + deltaMs;
    if (nextIn < 0) {
      nextIn = 0;
    }
    if (currentOut != null && nextIn >= currentOut) {
      nextIn = currentOut - 1;
      if (nextIn < 0) {
        nextIn = 0;
      }
    }
    await repository.updateClipRange(
      clipId: item.id,
      inMs: nextIn,
      outMs: currentOut,
    );
    await _reloadFromRepository();
  }

  Future<void> nudgeSelectedClipEnd(int deltaMs) async {
    final MediaRepository? repository = _mediaRepository;
    final MediaListItem? item = selectedItem;
    if (repository == null ||
        item == null ||
        item.type != MediaListItemType.clip) {
      return;
    }
    final int currentIn = item.clip!.inMs;
    final int? currentOut = item.clip!.outMs;
    if (currentOut == null) {
      return;
    }
    int nextOut = currentOut + deltaMs;
    if (nextOut <= currentIn) {
      nextOut = currentIn + 1;
    }
    await repository.updateClipRange(
      clipId: item.id,
      inMs: currentIn,
      outMs: nextOut,
    );
    await _reloadFromRepository();
  }

  Future<void> _reloadFromRepository() async {
    final MediaRepository? repository = _mediaRepository;
    if (repository == null) {
      return;
    }
    final Map<String, List<MediaTagAttachment>> attachmentsBefore =
        <String, List<MediaTagAttachment>>{
          for (final MapEntry<String, List<MediaTagAttachment>> e
              in _tagAttachmentsByItemKey.entries)
            e.key: List<MediaTagAttachment>.from(e.value),
        };
    final List<MediaListItem> items = await repository.listMixedItems();
    final Map<String, Set<String>> tagsByItemKey = await repository
        .listTagsForItems(items);
    final Map<String, List<MediaTagAttachment>> attachmentsByKey =
        await repository.listMediaTagAttachmentsForItems(items);
    _allItems = items;
    _tagsByItemKey
      ..clear()
      ..addAll(tagsByItemKey);
    _tagAttachmentsByItemKey
      ..clear()
      ..addAll(attachmentsByKey);
    _allTags
      ..clear()
      ..addAll(await repository.listAllTags());
    _savedTagEntries
      ..clear()
      ..addAll(await repository.listSavedTags());
    if (_selectedItemKey != null &&
        !_allItems.any(
          (MediaListItem item) => item.stableKey == _selectedItemKey,
        )) {
      _selectedItemKey = null;
    }
    final Set<String> validKeys =
        _allItems.map((MediaListItem i) => i.stableKey).toSet();
    _semanticTagSnapshotByItemKey.removeWhere(
      (String k, int _) => !validKeys.contains(k),
    );
    final Set<String> snapKeys = Set<String>.from(attachmentsBefore.keys)
      ..addAll(attachmentsByKey.keys);
    for (final String k in snapKeys) {
      if (!validKeys.contains(k)) {
        continue;
      }
      final List<MediaTagAttachment> ba = List<MediaTagAttachment>.from(
        attachmentsBefore[k] ?? const <MediaTagAttachment>[],
      );
      final List<MediaTagAttachment> bb = List<MediaTagAttachment>.from(
        attachmentsByKey[k] ?? const <MediaTagAttachment>[],
      );
      if (!_semanticTagAttachmentSnapshotsEqual(ba, bb)) {
        _semanticTagSnapshotByItemKey[k] =
            (_semanticTagSnapshotByItemKey[k] ?? 0) + 1;
      }
    }
    _applyFilters();
    _reconcilePreviewOsgPresetVisibilityForSelectedItem();
    notifyListeners();
  }

  Future<void> _loadWorkspaceSettings() async {
    final MediaRepository? repository = _mediaRepository;
    if (repository == null) {
      return;
    }
    _workspaceSettings = await repository.loadWorkspaceSettings();
    _syncIngestionConcurrencyFromWorkspace();
    _maybeApplyInitialClipVolumeFromWorkspace();
  }

  void _maybeApplyInitialClipVolumeFromWorkspace() {
    if (_clipVolumeInitializedFromWorkspace) {
      return;
    }
    final WorkspaceSettingsBundle? bundle = _workspaceSettings;
    if (bundle == null) {
      return;
    }
    _clipVolume = PlaybackVolumeDefaults.clamp(bundle.defaultClipVolume);
    _preMuteClipVolume = _clipVolume;
    _clipMuted = false;
    _clipVolumeInitializedFromWorkspace = true;
  }

  void _syncIngestionConcurrencyFromWorkspace() {
    final WorkspaceSettingsBundle? bundle = _workspaceSettings;
    if (bundle == null) {
      return;
    }
    _ingestionService.applyIngestionConcurrency(
      probeConcurrency: bundle.ingestProbeConcurrency,
      thumbnailConcurrency: bundle.ingestThumbnailConcurrency,
    );
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

  Future<void> saveFvpLogVerbosity(FvpLogVerbosity value) async {
    final MediaRepository? repository = _mediaRepository;
    if (repository == null) {
      return;
    }
    await repository.saveFvpLogVerbosity(value);
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

  Future<void> addWebhookSceneSwitchConfig(
    WebhookSceneSwitchConfig value,
  ) async {
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
    final Map<String, Set<String>> tagsByItem = await repository
        .listTagsForItems(items);
    final Map<String, List<MediaTagAttachment>> attachmentsByItem =
        await repository.listMediaTagAttachmentsForItems(items);
    final WorkspaceSettingsBundle settings = await repository
        .loadWorkspaceSettings();
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
        "fvpLogVerbosity": settings.fvpLogVerbosity.name,
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
                  "captureScene": settings.obsSceneSwitchConfig!.captureScene,
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
        "capturePaths": <String, Object?>{
          "recordingRelativeDir":
              settings.capturePathsSettings.recordingRelativeDir,
          "outputRelativeDir": settings.capturePathsSettings.outputRelativeDir,
        },
        "playoutRecordPaths": <String, Object?>{
          "stagingRelativeDir":
              settings.playoutRecordPathsSettings.stagingRelativeDir,
          "outputRelativeDir":
              settings.playoutRecordPathsSettings.outputRelativeDir,
        },
        "ignoredFolders": settings.ignoredFolders,
        "playoutOutput": <String, Object?>{
          "width": settings.playoutOutputSize.width,
          "height": settings.playoutOutputSize.height,
        },
        "osgPresets": jsonDecode(settings.osgWorkspaceConfig.encodeToStorageJson()),
        "tagSemanticTypes": settings.tagSemanticTypes
            .map(
              (TagSemanticType t) => <String, Object?>{
                "id": t.id,
                "name": t.name,
                "iconCodePoint": t.iconCodePoint,
              },
            )
            .toList(),
      },
      "mediaItems": items.map((MediaListItem item) {
        final bool isClip = item.type == MediaListItemType.clip;
        return <String, Object?>{
          "identifier": isClip ? item.stableKey : item.fileName,
          "fileName": item.fileName,
          "displayNameOverride": isClip
              ? item.clip!.displayNameOverride
              : item.master!.displayNameOverride,
          "relativePath": WorkspaceMediaPaths.displayRelativeToWorkspace(
            workspaceRoot,
            item.filePath,
          ),
          "tags": (tagsByItem[item.stableKey] ?? <String>{}).toList()..sort(),
          "tagRows": (attachmentsByItem[item.stableKey] ?? <MediaTagAttachment>[])
              .map(
                (MediaTagAttachment a) => <String, Object?>{
                  "tagName": a.tagName,
                  "semanticTypeId": a.semanticTypeId,
                  "semanticTypeIconCodePoint": a.semanticTypeIconCodePoint,
                },
              )
              .toList(),
          "clipRange": isClip
              ? <String, Object?>{
                  "inMs": item.clip!.inMs,
                  "outMs": item.clip!.outMs,
                }
              : null,
        };
      }).toList(),
    };
    await File(
      outputPath,
    ).writeAsString(const JsonEncoder.withIndent("  ").convert(payload));
  }

  Future<void> _refreshTagsForItems(
    List<MediaListItem> items, {
    required bool refreshAllTags,
  }) async {
    final MediaRepository? repository = _mediaRepository;
    if (repository == null || items.isEmpty) {
      return;
    }
    final Map<String, Set<String>> tagsByItemKey = await repository
        .listTagsForItems(items);
    final Map<String, List<MediaTagAttachment>> attachmentsByKey =
        await repository.listMediaTagAttachmentsForItems(items);
    for (final MediaListItem item in items) {
      _tagsByItemKey[item.stableKey] =
          tagsByItemKey[item.stableKey] ?? <String>{};
      _tagAttachmentsByItemKey[item.stableKey] =
          attachmentsByKey[item.stableKey] ?? <MediaTagAttachment>[];
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
              ? item.filePath.toLowerCase().contains(fileNameSearch) ||
                    item.fileName.toLowerCase().contains(fileNameSearch) ||
                    item.displayName.toLowerCase().contains(fileNameSearch)
              : item.fileName.toLowerCase().contains(fileNameSearch) ||
                    item.displayName.toLowerCase().contains(fileNameSearch))) {
        return false;
      }
      final int? clipMasterId = _clipsOfMasterFilterMediaId;
      if (clipMasterId != null) {
        if (item.type != MediaListItemType.clip ||
            item.clip!.masterMediaId != clipMasterId) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  bool _isUserTag(String tag) =>
      tag != MediaRepository.masterTag && tag != MediaRepository.clipTag;

  void setPlayoutActive(bool active) {
    _ingestionService.setPlayoutActive(active);
    if (active) {
      _previewPlayerInitNotBefore = null;
    } else {
      _previewPlayerInitNotBefore = DateTime.now().add(
        _kPreviewPlayerInitDelayAfterPlayout,
      );
    }
  }

  static const Duration _kPreviewPlayerInitDelayAfterPlayout = Duration(
    milliseconds: 450,
  );

  /// Lets the dashboard preview [ClipPlayerView] wait briefly after playout ends
  /// so the prior player can finish native teardown before a new decoder opens.
  Future<void> awaitPreviewPlayerInitGate() async {
    final DateTime? until = _previewPlayerInitNotBefore;
    if (until == null) {
      return;
    }
    final DateTime now = DateTime.now();
    if (until.isAfter(now)) {
      await Future<void>.delayed(until.difference(now));
    }
    _previewPlayerInitNotBefore = null;
  }

  void setPreviewPlaying(bool playing) {
    _dashboardPreviewPlaybackActive = playing;
    _syncIngestPreviewPause();
  }

  void _syncIngestPreviewPause() {
    final bool shouldPause =
        pauseIngestScanDuringPreview && _dashboardPreviewPlaybackActive;
    _ingestionService.setPreviewPlaying(shouldPause);
  }

  Future<void> savePauseIngestScanDuringPreview(bool value) async {
    final MediaRepository? repository = _mediaRepository;
    if (repository == null) {
      return;
    }
    await repository.savePauseIngestScanDuringPreview(value);
    await _loadWorkspaceSettings();
    _syncIngestPreviewPause();
    notifyListeners();
  }

  Future<void> saveIngestProbeConcurrency(int value) async {
    final MediaRepository? repository = _mediaRepository;
    if (repository == null) {
      return;
    }
    await repository.saveIngestProbeConcurrency(value);
    await _loadWorkspaceSettings();
    notifyListeners();
  }

  Future<void> saveIngestThumbnailConcurrency(int value) async {
    final MediaRepository? repository = _mediaRepository;
    if (repository == null) {
      return;
    }
    await repository.saveIngestThumbnailConcurrency(value);
    await _loadWorkspaceSettings();
    notifyListeners();
  }

  Future<void> saveDefaultClipVolume(double value) async {
    final MediaRepository? repository = _mediaRepository;
    if (repository == null) {
      return;
    }
    await repository.saveDefaultClipVolume(value);
    await _loadWorkspaceSettings();
    // Apply to the active session as well so the user hears the change
    // immediately.
    final double clamped = PlaybackVolumeDefaults.clamp(value);
    _clipVolume = clamped;
    _preMuteClipVolume = clamped;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_mediaSubscription?.cancel());
    unawaited(_thumbnailSubscription?.cancel());
    unawaited(_ingestionService.dispose());
    super.dispose();
  }
}
