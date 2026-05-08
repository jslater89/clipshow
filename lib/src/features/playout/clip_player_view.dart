import "dart:io";

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:logging/logging.dart";
import "package:video_player/video_player.dart";

class SeekBackwardIntent extends Intent {
  const SeekBackwardIntent();
}

class SeekForwardIntent extends Intent {
  const SeekForwardIntent();
}

class SeekShortBackwardIntent extends Intent {
  const SeekShortBackwardIntent();
}

class SeekShortForwardIntent extends Intent {
  const SeekShortForwardIntent();
}

class SeekLongBackwardIntent extends Intent {
  const SeekLongBackwardIntent();
}

class SeekLongForwardIntent extends Intent {
  const SeekLongForwardIntent();
}

class MarkInIntent extends Intent {
  const MarkInIntent();
}

class MarkOutIntent extends Intent {
  const MarkOutIntent();
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
    this.shortSeekStep = const Duration(seconds: 1),
    this.longSeekStep = const Duration(seconds: 15),
    this.overlay,
    this.onEscapePressed,
    this.onPositionChanged,
    this.onMarkInRequested,
    this.onMarkOutRequested,
  });

  final String filePath;
  final int startTimeMs;
  final int? endTimeMs;
  final bool autoPlay;
  final bool showControls;
  final Duration seekStep;
  final Duration shortSeekStep;
  final Duration longSeekStep;
  final Widget? overlay;
  final Future<void> Function()? onEscapePressed;
  final ValueChanged<int>? onPositionChanged;
  final VoidCallback? onMarkInRequested;
  final VoidCallback? onMarkOutRequested;

  @override
  State<ClipPlayerView> createState() => _ClipPlayerViewState();
}

class _ClipPlayerViewState extends State<ClipPlayerView> {
  final Logger _logger = Logger("ClipPlayerView");
  VideoPlayerController? _controller;
  String? _errorMessage;
  bool _isEscaping = false;

  @override
  void initState() {
    super.initState();
    _initializeController();
  }

  @override
  void didUpdateWidget(covariant ClipPlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath ||
        oldWidget.startTimeMs != widget.startTimeMs ||
        oldWidget.endTimeMs != widget.endTimeMs ||
        oldWidget.autoPlay != widget.autoPlay ||
        oldWidget.showControls != widget.showControls) {
      _disposeController();
      _initializeController();
    }
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
      await controller.seekTo(Duration(milliseconds: widget.startTimeMs));
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
      if (currentMs >= endMs && controller.value.isPlaying) {
        controller.pause();
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

  Future<void> _handleEscape() async {
    final Future<void> Function()? onEscapePressed = widget.onEscapePressed;
    if (onEscapePressed == null || _isEscaping) {
      return;
    }
    _isEscaping = true;
    await onEscapePressed();
    _isEscaping = false;
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  void _disposeController() {
    _controller?.removeListener(_handlePlaybackProgress);
    _controller?.dispose();
    _controller = null;
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.space): const ActivateIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft):
            const SeekBackwardIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowRight):
            const SeekForwardIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true):
            const SeekShortBackwardIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true):
            const SeekShortForwardIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true):
            const SeekLongBackwardIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowRight, control: true):
            const SeekLongForwardIntent(),
        if (widget.onMarkInRequested != null)
          const SingleActivator(LogicalKeyboardKey.keyI): const MarkInIntent(),
        if (widget.onMarkOutRequested != null)
          const SingleActivator(LogicalKeyboardKey.keyO): const MarkOutIntent(),
        if (widget.onEscapePressed != null)
          const SingleActivator(LogicalKeyboardKey.escape):
              const DismissIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _togglePlayPause();
              return null;
            },
          ),
          SeekBackwardIntent: CallbackAction<SeekBackwardIntent>(
            onInvoke: (_) {
              _seekBy(-widget.seekStep);
              return null;
            },
          ),
          SeekForwardIntent: CallbackAction<SeekForwardIntent>(
            onInvoke: (_) {
              _seekBy(widget.seekStep);
              return null;
            },
          ),
          SeekShortBackwardIntent: CallbackAction<SeekShortBackwardIntent>(
            onInvoke: (_) {
              _seekBy(-widget.shortSeekStep);
              return null;
            },
          ),
          SeekShortForwardIntent: CallbackAction<SeekShortForwardIntent>(
            onInvoke: (_) {
              _seekBy(widget.shortSeekStep);
              return null;
            },
          ),
          SeekLongBackwardIntent: CallbackAction<SeekLongBackwardIntent>(
            onInvoke: (_) {
              _seekBy(-widget.longSeekStep);
              return null;
            },
          ),
          SeekLongForwardIntent: CallbackAction<SeekLongForwardIntent>(
            onInvoke: (_) {
              _seekBy(widget.longSeekStep);
              return null;
            },
          ),
          MarkInIntent: CallbackAction<MarkInIntent>(
            onInvoke: (_) {
              widget.onMarkInRequested?.call();
              return null;
            },
          ),
          MarkOutIntent: CallbackAction<MarkOutIntent>(
            onInvoke: (_) {
              widget.onMarkOutRequested?.call();
              return null;
            },
          ),
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              _handleEscape();
              return null;
            },
          ),
        },
        child: Focus(autofocus: true, child: _buildBody()),
      ),
    );
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
