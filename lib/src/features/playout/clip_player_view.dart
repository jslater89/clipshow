import "dart:io";
import "dart:async";

import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:video_player/video_player.dart";

class ClipPlayerController {
  _ClipPlayerViewState? _state;

  Future<void> togglePlayPause() async {
    await _state?._togglePlayPause();
  }

  Future<void> seekBy(Duration offset) async {
    await _state?._seekBy(offset);
  }

  void _attach(_ClipPlayerViewState state) {
    _state = state;
  }

  void _detach(_ClipPlayerViewState state) {
    if (_state == state) {
      _state = null;
    }
  }
}

class ClipPlayerView extends StatefulWidget {
  const ClipPlayerView({
    super.key,
    required this.filePath,
    this.startTimeMs = 0,
    this.endTimeMs,
    this.autoPlay = false,
    this.showControls = false,
    this.seekStep = const Duration(seconds: 5),
    this.overlay,
    this.onPositionChanged,
    this.controller,
  });

  final String filePath;
  final int startTimeMs;
  final int? endTimeMs;
  final bool autoPlay;
  final bool showControls;
  final Duration seekStep;
  final Widget? overlay;
  final ValueChanged<int>? onPositionChanged;
  final ClipPlayerController? controller;

  @override
  State<ClipPlayerView> createState() => _ClipPlayerViewState();
}

class _ClipPlayerViewState extends State<ClipPlayerView> {
  final Logger _logger = Logger("ClipPlayerView");
  VideoPlayerController? _controller;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
    unawaited(_reinitializeController(reason: "initState"));
  }

  @override
  void didUpdateWidget(covariant ClipPlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
    if (oldWidget.filePath != widget.filePath ||
        oldWidget.startTimeMs != widget.startTimeMs ||
        oldWidget.endTimeMs != widget.endTimeMs ||
        oldWidget.autoPlay != widget.autoPlay ||
        oldWidget.showControls != widget.showControls) {
      _reinitializeController(reason: "didUpdateWidget");
    }
  }

  Future<void> _reinitializeController({required String reason}) async {
    _logger.info("Reinitializing controller due to $reason");
    await _disposeController();
    await _initializeController();
  }

  Future<void> _initializeController() async {
    setState(() {
      _errorMessage = null;
    });

    try {
      final VideoPlayerController controller = VideoPlayerController.file(
        File(widget.filePath),
      );
      _controller = controller;
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      await controller.seekTo(Duration(milliseconds: widget.startTimeMs));
      if (!mounted) {
        await controller.dispose();
        return;
      }
      controller.addListener(_handlePlaybackProgress);
      if (widget.autoPlay) {
        await controller.play();
      }
      if (mounted) {
        setState(() {});
      }
    } catch (error) {
      _logger.severe(
        "Failed to initialize player for ${widget.filePath}: $error",
      );
      if (mounted) {
        setState(() {
          _errorMessage = "Unable to load selected media.";
        });
      }
    }
  }

  void _handlePlaybackProgress() {
    final VideoPlayerController? controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    final int? endMs = widget.endTimeMs;
    if (endMs != null) {
      final int currentMs = controller.value.position.inMilliseconds;
      if (currentMs > endMs) {
        if (controller.value.isPlaying) {
          controller.pause();
        }
        controller.seekTo(Duration(milliseconds: endMs));
      }
    }
    widget.onPositionChanged?.call(controller.value.position.inMilliseconds);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _togglePlayPause() async {
    final VideoPlayerController? controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
  }

  Future<void> _seekBy(Duration offset) async {
    final VideoPlayerController? controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    final Duration position = controller.value.position;
    final Duration duration = controller.value.duration;
    final Duration clipStart = Duration(milliseconds: widget.startTimeMs);
    Duration next = position + offset;
    if (next < clipStart) {
      next = clipStart;
    }

    if (widget.endTimeMs != null) {
      final Duration clipEnd = Duration(milliseconds: widget.endTimeMs!);
      if (next > clipEnd) {
        next = clipEnd;
      }
    } else if (duration > Duration.zero && next > duration) {
      next = duration;
    }

    await controller.seekTo(next);
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    unawaited(_disposeController());
    super.dispose();
  }

  Future<void> _disposeController() async {
    final VideoPlayerController? controller = _controller;
    controller?.removeListener(_handlePlaybackProgress);
    if (controller != null) {
      await controller.dispose();
    }
    _controller = null;
  }


  @override
  Widget build(BuildContext context) {
    return Focus(autofocus: true, child: _buildBody());
  }

  Widget _buildBody() {
    final VideoPlayerController? controller = _controller;
    if (_errorMessage != null) {
      return Center(
        child: Text(
          _errorMessage!,
          style: const TextStyle(color: Colors.white),
        ),
      );
    }
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Column(
          children: <Widget>[
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _togglePlayPause,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(
                    width: controller.value.size.width,
                    height: controller.value.size.height,
                    child: VideoPlayer(controller),
                  ),
                ),
              ),
            ),
            if (widget.showControls) _buildControls(controller),
          ],
        ),
        if (widget.overlay != null) widget.overlay!,
      ],
    );
  }

  Widget _buildControls(VideoPlayerController controller) {
    return Container(
      color: Colors.black.withValues(alpha: 0.65),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          VideoProgressIndicator(
            controller,
            allowScrubbing: true,
            padding: const EdgeInsets.symmetric(vertical: 4),
          ),
          Row(
            children: <Widget>[
              IconButton(
                tooltip: "Back 5 Seconds",
                onPressed: () => _seekBy(-widget.seekStep),
                icon: const Icon(Icons.replay_5),
                color: Colors.white,
              ),
              IconButton(
                tooltip: controller.value.isPlaying ? "Pause" : "Play",
                onPressed: _togglePlayPause,
                icon: Icon(
                  controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                ),
                color: Colors.white,
              ),
              IconButton(
                tooltip: "Forward 5 Seconds",
                onPressed: () => _seekBy(widget.seekStep),
                icon: const Icon(Icons.forward_5),
                color: Colors.white,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "${_formatDuration(controller.value.position)} / ${_formatDuration(controller.value.duration)}",
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final int totalSeconds = duration.inSeconds;
    final int hours = totalSeconds ~/ 3600;
    final int minutes = (totalSeconds % 3600) ~/ 60;
    final int seconds = totalSeconds % 60;
    if (hours > 0) {
      return "$hours:${minutes.toString().padLeft(2, "0")}:${seconds.toString().padLeft(2, "0")}";
    }
    return "${minutes.toString().padLeft(2, "0")}:${seconds.toString().padLeft(2, "0")}";
  }
}
