import "dart:io";
import "dart:convert";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:logging/logging.dart";
import "package:provider/provider.dart";
import "package:window_manager/window_manager.dart";
import "dart:async";

import "package:obs_clipshow/src/app/ui_scale.dart";
import "package:obs_clipshow/src/features/dashboard/dashboard_screen.dart";
import "package:obs_clipshow/src/workspace/workspace_preferences.dart";
import "package:obs_clipshow/src/features/dashboard/dashboard_view_model.dart";
import "package:obs_clipshow/src/features/playout/playout_clip.dart";
import "package:obs_clipshow/src/features/playout/playout_framework_compositing_strip.dart";
import "package:obs_clipshow/src/features/playout/playout_screen.dart";
import "package:obs_clipshow/src/features/osg_mode/osg_mode_screen.dart";
import "package:obs_clipshow/src/features/osg_mode/osg_mode_session.dart";
import "package:obs_clipshow/src/features/workspace_settings/workspace_settings_dialog.dart";
import "package:obs_clipshow/src/media/media_list_item.dart";
import "package:obs_clipshow/src/obs/obs_service.dart";
import "package:obs_clipshow/src/osg/osg_models.dart";
import "package:obs_clipshow/src/util/reveal_file_in_folder.dart";
import "package:obs_clipshow/src/workspace/workspace_settings.dart";
import "package:path/path.dart" as p;

enum PlayoutWindowMode { windowed, fullscreen }

enum _SceneSwitchTarget { face, video, osg }

class ObsClipshowApp extends StatefulWidget {
  const ObsClipshowApp({super.key});

  @override
  State<ObsClipshowApp> createState() => _ObsClipshowAppState();
}

class _IncreaseUiScaleIntent extends Intent {
  const _IncreaseUiScaleIntent();
}

class _DecreaseUiScaleIntent extends Intent {
  const _DecreaseUiScaleIntent();
}

class _ObsClipshowAppState extends State<ObsClipshowApp> {
  final Logger _logger = Logger("ObsClipshowApp");
  final WorkspacePreferences _appPreferences = WorkspacePreferences();
  static const PlayoutWindowMode _playoutWindowMode =
      PlayoutWindowMode.windowed;
  static const Size _fallbackPlayoutSize = Size(1280, 720);
  late final DashboardViewModel _viewModel;
  late final ObsService _obsService;
  final ScrollController _dashboardScrollController = ScrollController();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  double _lastDashboardScrollOffset = 0;
  Rect? _prePlayoutBounds;
  bool _wasMaximizedBeforePlayout = false;
  PlayoutClip? _activeClip;
  OsgModeSession? _activeOsgModeSession;
  Completer<void>? _playoutFirstFrameCompleter;
  bool _pendingPlayoutRecord = false;
  static const Duration _playoutFirstFrameTimeout = Duration(seconds: 30);
  Timer? _obsPingTimer;
  String? _obsConfigKey;
  bool _obsPingInFlight = false;
  bool? _obsConnectionHealthy;
  DateTime? _lastSuccessfulObsPingAt;
  double _uiScale = 1;
  final PlayoutRootCompositingOverlay _playoutRootCompositingOverlay =
      PlayoutRootCompositingOverlay();

  @override
  void initState() {
    super.initState();
    _viewModel = DashboardViewModel.create();
    _obsService = ObsService();
    _viewModel.addListener(_handleViewModelChanged);
    _unlockAspectRatio();
    _viewModel.initialize();
    unawaited(_restoreUiScale());
  }

  Future<void> _restoreUiScale() async {
    final double? saved = await _appPreferences.loadUiScale();
    if (!mounted || saved == null) {
      return;
    }
    final double clamped = saved.clamp(kMinUiScale, kMaxUiScale);
    setState(() {
      _uiScale = clamped;
    });
  }

  void _persistUiScale() {
    unawaited(_appPreferences.saveUiScale(_uiScale));
  }

  @override
  void dispose() {
    _playoutRootCompositingOverlay.unmount();
    _viewModel.removeListener(_handleViewModelChanged);
    _obsPingTimer?.cancel();
    unawaited(_obsService.close());
    _dashboardScrollController.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  void _handleViewModelChanged() {
    _syncObsMonitoringFromSettings();
  }

  void _syncObsMonitoringFromSettings() {
    final ObsSceneSwitchConfig? obsConfig = _viewModel.obsSceneSwitchConfig;
    if (obsConfig == null || !obsConfig.enabled) {
      _obsConfigKey = null;
      _stopObsPingLoop();
      if ((_obsConnectionHealthy != null || _lastSuccessfulObsPingAt != null) &&
          mounted) {
        setState(() {
          _obsConnectionHealthy = null;
          _lastSuccessfulObsPingAt = null;
        });
      }
      return;
    }
    final String nextKey =
        "${obsConfig.serverAddress}:${obsConfig.port}:${obsConfig.password}:${obsConfig.videoScene}:${obsConfig.faceScene}:${obsConfig.osgScene}";
    if (_obsConfigKey != nextKey) {
      _obsConfigKey = nextKey;
      if (mounted) {
        setState(() {
          _obsConnectionHealthy = false;
          _lastSuccessfulObsPingAt = null;
        });
      }
    }
    _startObsPingLoop();
    unawaited(_attemptObsPing());
  }

  Future<void> _attemptObsPing() async {
    if (_obsPingInFlight) {
      return;
    }
    final ObsSceneSwitchConfig? obsConfig = _viewModel.obsSceneSwitchConfig;
    if (obsConfig == null || !obsConfig.enabled) {
      return;
    }
    _obsPingInFlight = true;
    final ObsService service = _buildObsService(obsConfig);
    try {
      await service.ensureConnected();
      await service.close();
      _markObsRequestSuccess();
    } catch (_) {
      _markObsRequestFailure();
    } finally {
      _obsPingInFlight = false;
    }
  }

  void _markObsRequestSuccess() {
    final DateTime now = DateTime.now();
    if (mounted) {
      setState(() {
        _obsConnectionHealthy = true;
        _lastSuccessfulObsPingAt = now;
      });
    }
  }

  void _markObsRequestFailure() {
    if (_obsConnectionHealthy != false && mounted) {
      setState(() {
        _obsConnectionHealthy = false;
      });
    }
    _startObsPingLoop();
  }

  void _startObsPingLoop() {
    if (_obsPingTimer != null) {
      return;
    }
    _obsPingTimer = Timer.periodic(const Duration(seconds: 12), (Timer _) {
      unawaited(_attemptObsPing());
    });
  }

  void _stopObsPingLoop() {
    _obsPingTimer?.cancel();
    _obsPingTimer = null;
  }

  String? _formatHms(DateTime? value) {
    if (value == null) {
      return null;
    }
    final String hh = value.hour.toString().padLeft(2, "0");
    final String mm = value.minute.toString().padLeft(2, "0");
    final String ss = value.second.toString().padLeft(2, "0");
    return "$hh:$mm:$ss";
  }

  ObsService _buildObsService(ObsSceneSwitchConfig obsConfig) {
    return ObsService(
      url: "ws://${obsConfig.serverAddress}:${obsConfig.port}",
      password: obsConfig.password.isEmpty ? null : obsConfig.password,
      videoSceneName: obsConfig.videoScene,
      faceSceneName: obsConfig.faceScene,
      osgSceneName: obsConfig.osgScene,
    );
  }

  Future<void> _enterOsgMode(OsgModeSession session) async {
    _viewModel.setPlayoutActive(true);
    if (_dashboardScrollController.hasClients) {
      _lastDashboardScrollOffset = _dashboardScrollController.offset;
    }
    try {
      _prePlayoutBounds = await windowManager.getBounds();
    } catch (error) {
      _logger.warning("Unable to capture window bounds before OSG mode: $error");
    }

    await _applyPlayoutWindowMode(_viewModel.playoutOutputSize);
    setState(() {
      _activeOsgModeSession = session;
    });
    _schedulePlayoutCompositingOverlayMount();
  }

  Future<void> _onOsgModeFirstFrameReady() async {
    if (!mounted || _activeOsgModeSession == null) {
      return;
    }
    await _switchToOsgScene();
  }

  Future<void> _exitOsgMode() async {
    _playoutRootCompositingOverlay.unmount();
    await _switchToFaceScene();
    await windowManager.setFullScreen(false);
    await windowManager.setTitleBarStyle(TitleBarStyle.normal);
    await _unlockAspectRatio();
    if (_prePlayoutBounds != null) {
      try {
        await windowManager.setBounds(_prePlayoutBounds);
      } catch (error) {
        _logger.warning(
          "Unable to restore window bounds after OSG mode: $error",
        );
      }
    }
    if (_wasMaximizedBeforePlayout) {
      try {
        await windowManager.maximize();
      } catch (error) {
        _logger.warning(
          "Unable to re-maximize window after OSG mode: $error",
        );
      }
      _wasMaximizedBeforePlayout = false;
    }
    setState(() {
      _activeOsgModeSession = null;
    });
    _viewModel.setPlayoutActive(false);
    unawaited(_restoreDashboardScrollOffset());
  }

  Future<OsgModeSession?> _switchOsgModeQuickSlot(int slotIndex) async {
    final OsgModeSession? next = _viewModel.buildOsgModeSessionForQuickSlot(
      slotIndex,
    );
    if (next == null) {
      return null;
    }
    setState(() {
      _activeOsgModeSession = next;
    });
    return next;
  }

  Future<void> _enterPlayout(PlayoutClip clip, {bool record = false}) async {
    _pendingPlayoutRecord = record;
    _playoutFirstFrameCompleter = Completer<void>();
    _viewModel.setPlayoutActive(true);
    if (_dashboardScrollController.hasClients) {
      _lastDashboardScrollOffset = _dashboardScrollController.offset;
    }
    try {
      _prePlayoutBounds = await windowManager.getBounds();
    } catch (error) {
      _logger.warning("Unable to capture window bounds before playout: $error");
    }

    await _applyPlayoutWindowMode(_viewModel.playoutOutputSize);
    setState(() {
      _activeClip = clip;
    });
    _schedulePlayoutCompositingOverlayMount();
    final Completer<void>? gate = _playoutFirstFrameCompleter;
    if (gate != null) {
      try {
        await gate.future.timeout(_playoutFirstFrameTimeout);
      } on TimeoutException {
        _logger.warning(
          "Playout first frame not ready within "
          "${_playoutFirstFrameTimeout.inSeconds}s; switching OBS anyway.",
        );
        _completePlayoutFirstFrameGate();
      }
    }
    if (!mounted || _activeClip == null) {
      return;
    }
    await _switchToVideoScene();
    if (_pendingPlayoutRecord) {
      final String? recordError = await _viewModel.startPlayoutRecord();
      if (recordError != null) {
        _showAppSnackBar(recordError);
      }
    }
    _pendingPlayoutRecord = false;
  }

  void _onPlayoutFirstFrameReady() {
    _completePlayoutFirstFrameGate();
    _playoutRootCompositingOverlay.mountFromNavigator(_navigatorKey);
  }

  void _completePlayoutFirstFrameGate() {
    final Completer<void>? gate = _playoutFirstFrameCompleter;
    if (gate != null && !gate.isCompleted) {
      gate.complete();
    }
    _playoutFirstFrameCompleter = null;
  }

  Future<void> _exitPlayout() async {
    _playoutRootCompositingOverlay.unmount();
    _completePlayoutFirstFrameGate();
    _pendingPlayoutRecord = false;
    String? exportedPath;
    String? exportError;
    if (_viewModel.obsPlayoutRecordActive) {
      final PlayoutRecordStopResult result =
          await _viewModel.stopPlayoutRecordAndCopy();
      exportedPath = result.destPath;
      exportError = result.errorMessage;
    }
    await _switchToFaceScene();
    await windowManager.setFullScreen(false);
    await windowManager.setTitleBarStyle(TitleBarStyle.normal);
    await _unlockAspectRatio();
    if (_prePlayoutBounds != null) {
      try {
        await windowManager.setBounds(_prePlayoutBounds);
      } catch (error) {
        _logger.warning(
          "Unable to restore window bounds after playout: $error",
        );
      }
    }
    if (_wasMaximizedBeforePlayout) {
      try {
        await windowManager.maximize();
      } catch (error) {
        _logger.warning(
          "Unable to re-maximize window after playout: $error",
        );
      }
      _wasMaximizedBeforePlayout = false;
    }
    setState(() {
      _activeClip = null;
    });
    _viewModel.setPlayoutActive(false);
    unawaited(_restoreDashboardScrollOffset());
    if (exportedPath != null) {
      _showPlayoutExportSuccessSnackBar(exportedPath);
    } else if (exportError != null) {
      _showAppSnackBar(exportError);
    }
  }

  void _showAppSnackBar(String message) {
    final BuildContext? ctx = _navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) {
      return;
    }
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showPlayoutExportSuccessSnackBar(String absolutePath) {
    final BuildContext? ctx = _navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) {
      return;
    }
    final String fileName = p.basename(absolutePath);
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text("Exported to $fileName"),
        action: SnackBarAction(
          label: "Reveal",
          onPressed: () {
            unawaited(() async {
              try {
                await revealFileInFolder(absolutePath);
              } catch (e) {
                _showAppSnackBar("Could not open file manager: $e");
              }
            }());
          },
        ),
      ),
    );
  }

  Future<void> _unlockAspectRatio() async {
    try {
      await windowManager.setAspectRatio(0);
    } catch (error) {
      _logger.warning("Unable to reset window aspect ratio constraint: $error");
    }
  }

  void _schedulePlayoutCompositingOverlayMount() {
    if (!kPlayoutFrameworkRootCompositingStrip) {
      return;
    }
    _playoutRootCompositingOverlay.resetMountAttempts();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || (_activeClip == null && _activeOsgModeSession == null)) {
        return;
      }
      _playoutRootCompositingOverlay.mountFromNavigator(_navigatorKey);
    });
  }

  Widget _buildHome(DashboardViewModel viewModel) {
    if (_activeClip != null) {
      return ChangeNotifierProvider<DashboardViewModel>.value(
        value: viewModel,
        child: PlayoutScreen(
          clip: _activeClip!,
          osgWorkspaceConfig: viewModel.osgWorkspaceConfig,
          workspaceRoot: viewModel.workspacePath ?? "",
          tagSemanticTypes: viewModel.tagSemanticTypes,
          telestratorDefaults: viewModel.telestratorDefaults,
          onResolveSemanticText: (int semanticTypeId) =>
              viewModel.resolveSemanticTagText(
                _activeClip!,
                semanticTypeId,
              ),
          onExitRequested: _exitPlayout,
          onFirstFrameReady: _onPlayoutFirstFrameReady,
        ),
      );
    }
    if (_activeOsgModeSession != null) {
      final OsgModeSession session = _activeOsgModeSession!;
      return ChangeNotifierProvider<DashboardViewModel>.value(
        value: viewModel,
        child: OsgModeScreen(
          session: session,
          osgWorkspaceConfig: viewModel.osgWorkspaceConfig,
          workspaceRoot: viewModel.workspacePath ?? "",
          tagSemanticTypes: viewModel.tagSemanticTypes,
          onResolveSemanticText: (int semanticTypeId) =>
              viewModel.resolveSemanticTagTextForMedia(
                mediaType: MediaListItemType.tagSet,
                mediaId: session.tagSetId,
                semanticTypeId: semanticTypeId,
              ),
          onExitRequested: _exitOsgMode,
          onFirstFrameReady: _onOsgModeFirstFrameReady,
          onTagSetQuickSlot: _switchOsgModeQuickSlot,
          onSessionChanged: (OsgModeSession next) {
            setState(() {
              _activeOsgModeSession = next;
            });
          },
        ),
      );
    }
    return DashboardScreen(
      viewModel: viewModel,
      onPlayClip: (PlayoutClip clip) => _enterPlayout(clip),
      onRecordClip: (PlayoutClip clip) => _enterPlayout(clip, record: true),
      onEnterOsgMode: _enterOsgMode,
      onWorkspaceSettingsRequested: _showWorkspaceSettings,
      obsConnectionHealthy: _obsConnectionHealthy,
      obsLastSuccessfulPingHms: _formatHms(_lastSuccessfulObsPingAt),
      scrollController: _dashboardScrollController,
    );
  }

  Future<void> _applyPlayoutWindowMode(PlayoutOutputSize output) async {
    _wasMaximizedBeforePlayout = false;
    try {
      if (await windowManager.isMaximized()) {
        _wasMaximizedBeforePlayout = true;
        await windowManager.unmaximize();
      }
    } catch (error) {
      _logger.warning(
        "Unable to query or leave maximized state before playout sizing: $error",
      );
    }

    final Size logical = output.size;
    final double aspect = logical.width / logical.height;
    await windowManager.setAspectRatio(aspect);
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden);

    if (_playoutWindowMode == PlayoutWindowMode.fullscreen) {
      await windowManager.setFullScreen(true);
      return;
    }

    await windowManager.setFullScreen(false);

    final Size targetSize = logical.width > 0 && logical.height > 0
        ? logical
        : _fallbackPlayoutSize;

    await windowManager.setSize(targetSize);
    await windowManager.center();
    await windowManager.focus();
  }

  Future<void> _restoreDashboardScrollOffset() async {
    for (int attempt = 0; attempt < 8; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 35));
      if (!mounted || !_dashboardScrollController.hasClients) {
        continue;
      }

      final double maxScrollExtent =
          _dashboardScrollController.position.maxScrollExtent;
      final bool canReachExactOffset =
          maxScrollExtent >= _lastDashboardScrollOffset;
      final double target = canReachExactOffset
          ? _lastDashboardScrollOffset
          : maxScrollExtent;

      _dashboardScrollController.jumpTo(target);

      if (canReachExactOffset) {
        return;
      }
    }
  }

  Future<void> _showWorkspaceSettings() async {
    final BuildContext? dialogContext = _navigatorKey.currentContext;
    if (dialogContext == null) {
      return;
    }
    await showDialog<void>(
      context: dialogContext,
      builder: (BuildContext context) {
        return ChangeNotifierProvider<DashboardViewModel>.value(
          value: _viewModel,
          child: const WorkspaceSettingsDialog(),
        );
      },
    );
  }

  Future<void> _switchToVideoScene() async {
    await _runSceneSwitch(target: _SceneSwitchTarget.video);
  }

  Future<void> _switchToFaceScene() async {
    await _runSceneSwitch(target: _SceneSwitchTarget.face);
  }

  Future<void> _switchToOsgScene() async {
    await _runSceneSwitch(target: _SceneSwitchTarget.osg);
  }

  Future<void> _runSceneSwitch({required _SceneSwitchTarget target}) async {
    final ObsSceneSwitchConfig? obsConfig = _viewModel.obsSceneSwitchConfig;
    final List<WebhookSceneSwitchConfig> webhooks =
        _viewModel.webhookSceneSwitchConfigs;
    bool attempted = false;
    if (obsConfig != null && obsConfig.enabled) {
      attempted = true;
      final ObsService service = _buildObsService(obsConfig);
      try {
        await service.ensureConnected();
        if (target == _SceneSwitchTarget.video) {
          await service.switchToVideoScene();
        } else if (target == _SceneSwitchTarget.osg) {
          await service.switchToOsgScene();
        } else {
          await service.switchToFaceScene();
        }
        _markObsRequestSuccess();
      } catch (error) {
        _markObsRequestFailure();
        _logger.warning("Unable to switch OBS scene using profile: $error");
      } finally {
        await service.close();
      }
    }
    for (final WebhookSceneSwitchConfig webhook in webhooks.where(
      (WebhookSceneSwitchConfig item) => item.enabled,
    )) {
      attempted = true;
      try {
        await _sendSceneSwitchWebhook(
          webhook,
          target: target,
        );
      } catch (error) {
        _logger.warning(
          "Unable to call scene-switch webhook ${webhook.name}: $error",
        );
      }
    }
    if (!attempted) {
      _logger.fine(
        "No scene-switch profile configured; skipping scene switch.",
      );
    }
  }

  Future<void> _sendSceneSwitchWebhook(
    WebhookSceneSwitchConfig webhook, {
    required _SceneSwitchTarget target,
  }) async {
    // Fixed tokens for receivers; not tied to OBS scene strings.
    final String sceneToken = switch (target) {
      _SceneSwitchTarget.video => "video",
      _SceneSwitchTarget.osg => "osg",
      _SceneSwitchTarget.face => "face",
    };
    final Uri uri = Uri.parse(webhook.url);
    final HttpClient client = HttpClient();
    try {
      if (webhook.method == WebhookMethod.get) {
        final String paramKey = webhook.getQueryParamName.trim().isEmpty
            ? "scene"
            : webhook.getQueryParamName.trim();
        final Uri requestUri = uri.replace(
          queryParameters: <String, String>{
            ...uri.queryParameters,
            paramKey: sceneToken,
          },
        );
        final HttpClientRequest request = await client.getUrl(requestUri);
        await request.close();
        return;
      }
      final HttpClientRequest request = await client.postUrl(uri);
      final String sceneKey = webhook.sceneKey.trim().isEmpty
          ? "scene"
          : webhook.sceneKey.trim();
      if (webhook.postBodyType == WebhookPostBodyType.form) {
        request.headers.contentType = ContentType(
          "application",
          "x-www-form-urlencoded",
          charset: "utf-8",
        );
        request.write(
          Uri(queryParameters: <String, String>{sceneKey: sceneToken}).query,
        );
      } else {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(<String, String>{sceneKey: sceneToken}));
      }
      await request.close();
    } finally {
      client.close(force: true);
    }
  }

  void _increaseUiScale() {
    setState(() {
      final double next = _uiScale + kUiScaleStep;
      _uiScale = next > kMaxUiScale ? kMaxUiScale : next;
    });
    _persistUiScale();
  }

  void _decreaseUiScale() {
    setState(() {
      final double next = _uiScale - kUiScaleStep;
      _uiScale = next < kMinUiScale ? kMinUiScale : next;
    });
    _persistUiScale();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      title: "Clipshow",
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blueGrey,
          brightness: Brightness.dark,
        ),
        brightness: Brightness.dark,
      ),
      builder: (BuildContext context, Widget? child) {
        final MediaQueryData mediaQueryData = MediaQuery.of(context);
        return UiScaleScope(
          scale: _uiScale,
          increaseScale: _increaseUiScale,
          decreaseScale: _decreaseUiScale,
          child: Shortcuts(
            shortcuts: const <ShortcutActivator, Intent>{
              SingleActivator(
                LogicalKeyboardKey.equal,
                control: true,
              ): _IncreaseUiScaleIntent(),
              SingleActivator(
                LogicalKeyboardKey.minus,
                control: true,
              ): _DecreaseUiScaleIntent(),
            },
            child: Actions(
              actions: <Type, Action<Intent>>{
                _IncreaseUiScaleIntent: CallbackAction<_IncreaseUiScaleIntent>(
                  onInvoke: (_) {
                    _increaseUiScale();
                    return null;
                  },
                ),
                _DecreaseUiScaleIntent: CallbackAction<_DecreaseUiScaleIntent>(
                  onInvoke: (_) {
                    _decreaseUiScale();
                    return null;
                  },
                ),
              },
              child: MediaQuery(
                data: mediaQueryData.copyWith(
                  textScaler: TextScaler.linear(_uiScale),
                ),
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          ),
        );
      },
      home: _buildHome(_viewModel),
    );
  }
}
