import "dart:io";
import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:screen_retriever/screen_retriever.dart";
import "package:window_manager/window_manager.dart";
import "dart:async";

import "../features/dashboard/dashboard_screen.dart";
import "../features/dashboard/dashboard_view_model.dart";
import "../features/playout/playout_clip.dart";
import "../features/playout/playout_screen.dart";
import "../media/master_media_file.dart";
import "../obs/obs_service.dart";

enum PlayoutWindowMode {
  windowed,
  fullscreen,
}

class ObsClipshowApp extends StatefulWidget {
  const ObsClipshowApp({super.key});

  @override
  State<ObsClipshowApp> createState() => _ObsClipshowAppState();
}

class _ObsClipshowAppState extends State<ObsClipshowApp> {
  final Logger _logger = Logger("ObsClipshowApp");
  static const PlayoutWindowMode _playoutWindowMode = PlayoutWindowMode.windowed;
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

  Future<void> _enterPlayout(MasterMediaFile mediaFile) async {
    if (_dashboardScrollController.hasClients) {
      _lastDashboardScrollOffset = _dashboardScrollController.offset;
    }
    final PlayoutClip clip = PlayoutClip(
      filePath: mediaFile.filePath,
      startTimeMs: 0,
      endTimeMs: null,
    );
    setState(() {
      _activeClip = clip;
    });

    try {
      _prePlayoutBounds = await windowManager.getBounds();
    } catch (error) {
      _logger.warning("Unable to capture window bounds before playout: $error");
    }

    await _applyPlayoutWindowMode(mediaFile.filePath);

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
        _logger.warning("Unable to restore window bounds after playout: $error");
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

  Size _fitWithin({
    required Size sourceSize,
    required Size bounds,
  }) {
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
      final ProcessResult result = await Process.run(
        "ffprobe",
        <String>[
          "-v",
          "error",
          "-select_streams",
          "v:0",
          "-show_entries",
          "stream=width,height",
          "-of",
          "csv=s=x:p=0",
          videoPath,
        ],
      );
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
      final bool canReachExactOffset = maxScrollExtent >= _lastDashboardScrollOffset;
      final double target = canReachExactOffset
          ? _lastDashboardScrollOffset
          : maxScrollExtent;

      _dashboardScrollController.jumpTo(target);

      if (canReachExactOffset) {
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Vanalyst Playout",
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
      ),
      home: _activeClip == null
          ? DashboardScreen(
              viewModel: _viewModel,
              onPlayMedia: _enterPlayout,
              scrollController: _dashboardScrollController,
            )
          : PlayoutScreen(
              clip: _activeClip!,
              onExitRequested: _exitPlayout,
            ),
    );
  }
}
