import "dart:io";
import "dart:convert";
import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:provider/provider.dart";
import "package:screen_retriever/screen_retriever.dart";
import "package:window_manager/window_manager.dart";
import "dart:async";

import 'package:obs_clipshow/src/features/dashboard/dashboard_screen.dart';
import 'package:obs_clipshow/src/features/dashboard/dashboard_view_model.dart';
import 'package:obs_clipshow/src/features/playout/playout_clip.dart';
import 'package:obs_clipshow/src/features/playout/playout_screen.dart';
import "package:obs_clipshow/src/features/workspace_settings/workspace_settings_dialog.dart";
import 'package:obs_clipshow/src/obs/obs_service.dart';
import "package:obs_clipshow/src/workspace/workspace_settings.dart";

enum PlayoutWindowMode { windowed, fullscreen }

class ObsClipshowApp extends StatefulWidget {
  const ObsClipshowApp({super.key});

  @override
  State<ObsClipshowApp> createState() => _ObsClipshowAppState();
}

class _ObsClipshowAppState extends State<ObsClipshowApp> {
  final Logger _logger = Logger("ObsClipshowApp");
  static const PlayoutWindowMode _playoutWindowMode =
      PlayoutWindowMode.windowed;
  static const Size _fallbackPlayoutSize = Size(1280, 720);
  late final DashboardViewModel _viewModel;
  late final ObsService _obsService;
  final ScrollController _dashboardScrollController = ScrollController();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  double _lastDashboardScrollOffset = 0;
  Rect? _prePlayoutBounds;
  PlayoutClip? _activeClip;
  Timer? _obsPingTimer;
  String? _obsConfigKey;
  bool _obsPingInFlight = false;
  bool? _obsConnectionHealthy;
  DateTime? _lastSuccessfulObsPingAt;

  @override
  void initState() {
    super.initState();
    _viewModel = DashboardViewModel.create();
    _obsService = ObsService();
    _viewModel.addListener(_handleViewModelChanged);
    _unlockAspectRatio();
    _viewModel.initialize();
  }

  @override
  void dispose() {
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
        "${obsConfig.serverAddress}:${obsConfig.port}:${obsConfig.password}:${obsConfig.videoScene}:${obsConfig.faceScene}";
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
    );
  }

  Future<void> _enterPlayout(PlayoutClip clip) async {
    _viewModel.setPlayoutActive(true);
    if (_dashboardScrollController.hasClients) {
      _lastDashboardScrollOffset = _dashboardScrollController.offset;
    }
    try {
      _prePlayoutBounds = await windowManager.getBounds();
    } catch (error) {
      _logger.warning("Unable to capture window bounds before playout: $error");
    }

    await _applyPlayoutWindowMode(clip.filePath);
    setState(() {
      _activeClip = clip;
    });
    await _switchToVideoScene();
  }

  Future<void> _exitPlayout() async {
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
    setState(() {
      _activeClip = null;
    });
    _viewModel.setPlayoutActive(false);
    unawaited(_restoreDashboardScrollOffset());
  }

  Future<void> _unlockAspectRatio() async {
    try {
      await windowManager.setAspectRatio(0);
    } catch (error) {
      _logger.warning("Unable to reset window aspect ratio constraint: $error");
    }
  }

  Future<void> _applyPlayoutWindowMode(String videoPath) async {
    await windowManager.setAspectRatio(16 / 9);
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden);

    if (_playoutWindowMode == PlayoutWindowMode.fullscreen) {
      await windowManager.setFullScreen(true);
      return;
    }

    await windowManager.setFullScreen(false);

    Size targetSize = _fallbackPlayoutSize;
    try {
      final Display display = await screenRetriever.getPrimaryDisplay();
      final Size screenSize = display.visibleSize ?? display.size;
      final Size? videoSize = await _probeVideoSize(videoPath);
      final Size sourceSize = videoSize ?? _fallbackPlayoutSize;
      targetSize = _fitWithin(
        sourceSize: sourceSize,
        bounds: Size(screenSize.width * 0.9, screenSize.height * 0.9),
      );
    } catch (error) {
      _logger.warning("Unable to calculate windowed playout size: $error");
    }

    await windowManager.setSize(targetSize);
    await windowManager.center();
    await windowManager.focus();
  }

  Size _fitWithin({required Size sourceSize, required Size bounds}) {
    final double widthScale = bounds.width / sourceSize.width;
    final double heightScale = bounds.height / sourceSize.height;
    final double scale = widthScale < heightScale ? widthScale : heightScale;
    final double rawWidth = sourceSize.width * scale;
    final double rawHeight = sourceSize.height * scale;
    final double width = rawWidth < 960 ? 960 : rawWidth;
    final double height = rawHeight < 540 ? 540 : rawHeight;
    return Size(width, height);
  }

  Future<Size?> _probeVideoSize(String videoPath) async {
    try {
      final ProcessResult result = await Process.run("ffprobe", <String>[
        "-v",
        "error",
        "-select_streams",
        "v:0",
        "-show_entries",
        "stream=width,height",
        "-of",
        "csv=s=x:p=0",
        videoPath,
      ]);
      if (result.exitCode != 0) {
        _logger.finer("ffprobe size failed: ${result.stderr}");
        return null;
      }
      final String out = (result.stdout as String).trim();
      final List<String> parts = out.split("x");
      if (parts.length != 2) {
        return null;
      }
      final double? width = double.tryParse(parts[0]);
      final double? height = double.tryParse(parts[1]);
      if (width == null || height == null || width <= 0 || height <= 0) {
        return null;
      }
      return Size(width, height);
    } catch (error) {
      _logger.finer("Unable to probe video size: $error");
      return null;
    }
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
    await _runSceneSwitch(enteringPlayout: true);
  }

  Future<void> _switchToFaceScene() async {
    await _runSceneSwitch(enteringPlayout: false);
  }

  Future<void> _runSceneSwitch({required bool enteringPlayout}) async {
    final ObsSceneSwitchConfig? obsConfig = _viewModel.obsSceneSwitchConfig;
    final List<WebhookSceneSwitchConfig> webhooks =
        _viewModel.webhookSceneSwitchConfigs;
    bool attempted = false;
    if (obsConfig != null && obsConfig.enabled) {
      attempted = true;
      final ObsService service = _buildObsService(obsConfig);
      try {
        await service.ensureConnected();
        if (enteringPlayout) {
          await service.switchToVideoScene();
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
          enteringPlayout: enteringPlayout,
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
    required bool enteringPlayout,
  }) async {
    final String sceneName = enteringPlayout ? "Video Scene" : "Face Scene";
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
            paramKey: sceneName,
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
          Uri(queryParameters: <String, String>{sceneKey: sceneName}).query,
        );
      } else {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(<String, String>{sceneKey: sceneName}));
      }
      await request.close();
    } finally {
      client.close(force: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: "Vanalyst Playout",
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blueGrey,
          brightness: Brightness.dark,
        ),
        brightness: Brightness.dark,
      ),
      home: _activeClip == null
          ? DashboardScreen(
              viewModel: _viewModel,
              onPlayClip: _enterPlayout,
              onWorkspaceSettingsRequested: _showWorkspaceSettings,
              obsConnectionHealthy: _obsConnectionHealthy,
              obsLastSuccessfulPingHms: _formatHms(_lastSuccessfulObsPingAt),
              scrollController: _dashboardScrollController,
            )
          : PlayoutScreen(clip: _activeClip!, onExitRequested: _exitPlayout),
    );
  }
}
