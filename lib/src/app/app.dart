import "dart:io";
import "dart:convert";
import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:screen_retriever/screen_retriever.dart";
import "package:window_manager/window_manager.dart";
import "dart:async";

import 'package:obs_clipshow/src/features/dashboard/dashboard_screen.dart';
import 'package:obs_clipshow/src/features/dashboard/dashboard_view_model.dart';
import 'package:obs_clipshow/src/features/playout/playout_clip.dart';
import 'package:obs_clipshow/src/features/playout/playout_screen.dart';
import 'package:obs_clipshow/src/obs/obs_service.dart';

enum PlayoutWindowMode { windowed, fullscreen }

class ObsClipshowApp extends StatefulWidget {
  const ObsClipshowApp({super.key});

  @override
  State<ObsClipshowApp> createState() => _ObsClipshowAppState();
}

class _ObsClipshowAppState extends State<ObsClipshowApp> {
  final Logger _logger = Logger("ObsClipshowApp");
  static const String _debugLogPath =
      "/home/jay/development/personal/obs_clipshow/.cursor/debug-c1d67a.log";
  static const PlayoutWindowMode _playoutWindowMode =
      PlayoutWindowMode.windowed;
  static const Size _fallbackPlayoutSize = Size(1280, 720);
  late final DashboardViewModel _viewModel;
  late final ObsService _obsService;
  final ScrollController _dashboardScrollController = ScrollController();
  double _lastDashboardScrollOffset = 0;
  Rect? _prePlayoutBounds;
  PlayoutClip? _activeClip;

  @override
  void initState() {
    super.initState();
    _viewModel = DashboardViewModel.create();
    _obsService = ObsService();
    _unlockAspectRatio();
    _viewModel.initialize();
  }

  @override
  void dispose() {
    unawaited(_obsService.close());
    _dashboardScrollController.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  Future<void> _enterPlayout(PlayoutClip clip) async {
    // #region agent log
    _debugLog(
      hypothesisId: "H3,H4",
      location: "app.dart:_enterPlayout:start",
      message: "Entering playout",
      data: <String, Object?>{
        "filePath": clip.filePath,
        "startTimeMs": clip.startTimeMs,
        "endTimeMs": clip.endTimeMs,
        "previousActiveClipPath": _activeClip?.filePath,
        "selectedItemKey": _viewModel.selectedItemKey,
      },
    );
    // #endregion
    if (_dashboardScrollController.hasClients) {
      _lastDashboardScrollOffset = _dashboardScrollController.offset;
    }
    try {
      _prePlayoutBounds = await windowManager.getBounds();
    } catch (error) {
      _logger.warning("Unable to capture window bounds before playout: $error");
    }

    await _applyPlayoutWindowMode(clip.filePath);
    // #region agent log
    _debugLog(
      hypothesisId: "H3",
      location: "app.dart:_enterPlayout:windowModeApplied",
      message: "Playout window mode applied",
      data: <String, Object?>{"filePath": clip.filePath},
    );
    // #endregion
    setState(() {
      _activeClip = clip;
    });
    // #region agent log
    _debugLog(
      hypothesisId: "H3,H4",
      location: "app.dart:_enterPlayout:activeClipSet",
      message: "Dashboard replaced by playout screen",
      data: <String, Object?>{"filePath": clip.filePath},
    );
    // #endregion

    try {
      await _obsService.ensureConnected();
      await _obsService.switchToVideoScene();
    } catch (error) {
      _logger.warning("Unable to switch OBS to video scene: $error");
    }
  }

  Future<void> _exitPlayout() async {
    try {
      await _obsService.ensureConnected();
      await _obsService.switchToFaceScene();
    } catch (error) {
      _logger.warning("Unable to switch OBS to face scene: $error");
    }
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
    // #region agent log
    _debugLog(
      hypothesisId: "H3",
      location: "app.dart:_applyPlayoutWindowMode:start",
      message: "Applying playout window mode",
      data: <String, Object?>{
        "videoPath": videoPath,
        "mode": _playoutWindowMode.name,
      },
    );
    // #endregion
    await windowManager.setAspectRatio(16 / 9);
    // #region agent log
    _debugLog(
      hypothesisId: "H3",
      location: "app.dart:_applyPlayoutWindowMode:afterSetAspectRatio",
      message: "Applied aspect ratio",
      data: <String, Object?>{"ratio": 16 / 9},
    );
    // #endregion
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    // #region agent log
    _debugLog(
      hypothesisId: "H3",
      location: "app.dart:_applyPlayoutWindowMode:afterSetTitleBarStyle",
      message: "Applied title bar style",
      data: <String, Object?>{"style": TitleBarStyle.hidden.name},
    );
    // #endregion

    if (_playoutWindowMode == PlayoutWindowMode.fullscreen) {
      await windowManager.setFullScreen(true);
      // #region agent log
      _debugLog(
        hypothesisId: "H3",
        location: "app.dart:_applyPlayoutWindowMode:afterSetFullScreenTrue",
        message: "Applied fullscreen true",
        data: <String, Object?>{},
      );
      // #endregion
      return;
    }

    await windowManager.setFullScreen(false);
    // #region agent log
    _debugLog(
      hypothesisId: "H3",
      location: "app.dart:_applyPlayoutWindowMode:afterSetFullScreenFalse",
      message: "Applied fullscreen false",
      data: <String, Object?>{},
    );
    // #endregion

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
    // #region agent log
    _debugLog(
      hypothesisId: "H3",
      location: "app.dart:_applyPlayoutWindowMode:afterSetSize",
      message: "Applied window size",
      data: <String, Object?>{
        "targetWidth": targetSize.width,
        "targetHeight": targetSize.height,
      },
    );
    // #endregion
    await windowManager.center();
    // #region agent log
    _debugLog(
      hypothesisId: "H3",
      location: "app.dart:_applyPlayoutWindowMode:afterCenter",
      message: "Applied window center",
      data: <String, Object?>{},
    );
    // #endregion
    await windowManager.focus();
    // #region agent log
    _debugLog(
      hypothesisId: "H3",
      location: "app.dart:_applyPlayoutWindowMode:end",
      message: "Window geometry and focus applied",
      data: <String, Object?>{
        "targetWidth": targetSize.width,
        "targetHeight": targetSize.height,
      },
    );
    // #endregion
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

  void _debugLog({
    required String hypothesisId,
    required String location,
    required String message,
    required Map<String, Object?> data,
    String runId = "initial",
  }) {
    final Map<String, Object?> payload = <String, Object?>{
      "sessionId": "c1d67a",
      "runId": runId,
      "hypothesisId": hypothesisId,
      "location": location,
      "message": message,
      "data": data,
      "timestamp": DateTime.now().millisecondsSinceEpoch,
    };
    unawaited(_appendDebugLog(payload));
  }

  Future<void> _appendDebugLog(Map<String, Object?> payload) async {
    try {
      await File(_debugLogPath).writeAsString(
        "${jsonEncode(payload)}\n",
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
              scrollController: _dashboardScrollController,
            )
          : PlayoutScreen(clip: _activeClip!, onExitRequested: _exitPlayout),
    );
  }
}
