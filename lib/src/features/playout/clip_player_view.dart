import "dart:io";
import "dart:async";

import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:video_player/video_player.dart";

import "package:obs_clipshow/src/app/ui_scale.dart";

class ClipPlayerController {
  _ClipPlayerViewState? _state;

  Future<void> togglePlayPause() async {
    await _state?._togglePlayPause();
  }

  Future<void> seekBy(Duration offset) async {
    await _state?._seekBy(offset);
  }

  Future<void> seekToStart() async {
    await _state?._seekToStart();
  }

  Future<void> seekToEnd() async {
    await _state?._seekToEnd();
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
    this.initialPositionMs,
    this.autoPlay = false,
    this.showControls = false,
    this.seekStep = const Duration(seconds: 5),
    this.clickTogglesPlayback = false,
    this.overlay,
    this.videoAreaOverlay,
    this.onPositionChanged,
    this.onPlayingChanged,
    this.controller,
    this.videoBoxFit = BoxFit.contain,
    this.volume = 1.0,
    this.beforeVideoInitialize,
  });

  final String filePath;
  final int startTimeMs;
  final int? endTimeMs;
  final int? initialPositionMs;
  final bool autoPlay;
  final bool showControls;
  final Duration seekStep;
  final bool clickTogglesPlayback;
  final Widget? overlay;

  /// Drawn in the letterboxed video area (same bounds as [VideoPlayer] with
  /// [videoBoxFit]), not over controls or unused pillar/letterbox outside the
  /// fitted frame.
  final Widget? videoAreaOverlay;
  final ValueChanged<int>? onPositionChanged;
  final ValueChanged<bool>? onPlayingChanged;
  final ClipPlayerController? controller;

  /// How the decoded video is fitted inside the player (e.g. [BoxFit.contain] vs [BoxFit.cover]).
  final BoxFit videoBoxFit;

  /// When non-null, awaited at the start of each video controller init (after
  /// dispose). Used e.g. to stagger dashboard preview init after playout teardown.
  final Future<void> Function()? beforeVideoInitialize;

  /// Audio volume in the range 0.0–1.0. Applied on init and whenever it changes
  /// (without reinitializing the underlying [VideoPlayerController]).
  final double volume;

  @override
  State<ClipPlayerView> createState() => _ClipPlayerViewState();
}

class _ClipPlayerViewState extends State<ClipPlayerView> {
  final Logger _logger = Logger("ClipPlayerView");
  VideoPlayerController? _controller;
  String? _errorMessage;
  bool _lastIsPlaying = false;

  /// Completes after all seeks issued through [ClipPlayerController] finish.
  /// Hotkeys call [seekBy] without awaiting, so [_togglePlayPause] drains this
  /// before starting playback.
  Future<void> _seekTail = Future<void>.value();

  /// The position the user most recently explicitly seeked to.
  ///
  /// Cleared after it is consumed in [_togglePlayPause], or when the user
  /// explicitly seeks to the clip end.
  Duration? _targetSeekPosition;

  /// Whether the video reached end-of-file since the last play.
  ///
  /// On Linux (and some other platforms) the media engine enters a hard
  /// EOS/stopped state on completion. In that state, [VideoPlayerController.seekTo]
  /// updates the Dart-side position but the platform ignores the seek. When
  /// [VideoPlayerController.play] is subsequently called the engine restarts
  /// from position 0 regardless of any pre-play seek.
  ///
  /// The fix is to call [play] first (which exits EOS), then issue a seek while
  /// the engine is actively playing — a flushing seek that is always honoured.
  /// We track this flag so we still know to do that even after [_seekBy] has
  /// already cleared [VideoPlayerValue.isCompleted] by moving the position.
  bool _reachedEnd = false;

  /// Paused on the last frame of the file (no clip end mark) so we avoid the
  /// platform EOS/stopped state where seeks are ignored until the controller is
  /// recreated ([_restartPlaybackFrom]).
  bool _naturalEndPauseApplied = false;

  static const Duration _naturalEndPauseLead = Duration(milliseconds: 100);

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
        oldWidget.initialPositionMs != widget.initialPositionMs ||
        oldWidget.autoPlay != widget.autoPlay ||
        oldWidget.showControls != widget.showControls) {
      _reinitializeController(reason: "didUpdateWidget");
    } else if (oldWidget.volume != widget.volume) {
      final VideoPlayerController? controller = _controller;
      if (controller != null && controller.value.isInitialized) {
        unawaited(controller.setVolume(widget.volume.clamp(0.0, 1.0)));
      }
    }
  }

  Future<void> _reinitializeController({required String reason}) async {
    _logger.info("Reinitializing controller due to $reason");
    _targetSeekPosition = null;
    _reachedEnd = false;
    _naturalEndPauseApplied = false;
    await _disposeController();
    await _initializeController();
  }

  Future<void> _initializeController() async {
    setState(() {
      _errorMessage = null;
    });

    final Future<void> Function()? gate = widget.beforeVideoInitialize;
    if (gate != null) {
      try {
        await gate();
      } catch (error, stackTrace) {
        _logger.warning(
          "beforeVideoInitialize failed: $error",
          error,
          stackTrace,
        );
      }
      if (!mounted) {
        return;
      }
    }

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
      Duration initialPosition = Duration(
        milliseconds: widget.initialPositionMs ?? widget.startTimeMs,
      );
      final Duration clipStart = Duration(milliseconds: widget.startTimeMs);
      if (initialPosition < clipStart) {
        initialPosition = clipStart;
      }
      final int? endMs = widget.endTimeMs;
      if (endMs != null) {
        final Duration clipEnd = Duration(milliseconds: endMs);
        if (initialPosition > clipEnd) {
          initialPosition = clipEnd;
        }
      }
      await controller.seekTo(initialPosition);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      await controller.setVolume(widget.volume.clamp(0.0, 1.0));
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

    if (controller.value.isCompleted) {
      _reachedEnd = true;
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
    } else {
      // Full file or open-ended clip: pause on the last frame *before* the
      // decoder latches to EOS, same idea as marking out on a bounded clip.
      final Duration duration = controller.value.duration;
      if (duration > Duration.zero && !_naturalEndPauseApplied) {
        final Duration position = controller.value.position;
        Duration lead = _naturalEndPauseLead;
        if (duration <= lead) {
          lead = Duration.zero;
        }
        final Duration threshold = duration - lead;
        final bool shouldFreeze =
            controller.value.isCompleted ||
            (controller.value.isPlaying && position >= threshold);
        if (shouldFreeze) {
          _naturalEndPauseApplied = true;
          unawaited(_freezeOnNaturalEnd(duration));
        }
      }
    }
    widget.onPositionChanged?.call(controller.value.position.inMilliseconds);
    final bool isPlaying = controller.value.isPlaying;
    if (isPlaying != _lastIsPlaying) {
      _lastIsPlaying = isPlaying;
      widget.onPlayingChanged?.call(isPlaying);
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _freezeOnNaturalEnd(Duration duration) async {
    final VideoPlayerController? controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    try {
      if (controller.value.isPlaying) {
        await controller.pause();
      }
      await controller.seekTo(duration);
      _reachedEnd = true;
    } catch (error, stackTrace) {
      _logger.warning(
        "freezeOnNaturalEnd failed: $error",
        error,
        stackTrace,
      );
    }
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
      return;
    }

    await _enqueueSeek(() async {});

    final bool hadReachedEnd = _reachedEnd;
    _reachedEnd = false;
    final Duration? target = _targetSeekPosition;
    _targetSeekPosition = null;

    if (hadReachedEnd) {
      // After EOS the underlying engine (fvp/mpv) is in a stopped state where
      // seeks are unreliable and play() restarts from the beginning regardless
      // of the Dart-side position. The only reliable fix is to create a fresh
      // controller at the desired position. We initialise it while the old one
      // is still active so there is no black-screen gap.
      final Duration playFrom =
          target ?? Duration(milliseconds: widget.startTimeMs);
      await _restartPlaybackFrom(playFrom);
    } else {
      await controller.play();
    }
  }

  /// Initialises a new [VideoPlayerController] for the same file at [position],
  /// swaps it in while the old controller is still displaying (no black flash),
  /// then starts playback.
  Future<void> _restartPlaybackFrom(Duration position) async {
    final VideoPlayerController newController = VideoPlayerController.file(
      File(widget.filePath),
    );
    try {
      await newController.initialize();
      if (!mounted) {
        await newController.dispose();
        return;
      }
      await newController.seekTo(position);
      if (!mounted) {
        await newController.dispose();
        return;
      }
      await newController.setVolume(widget.volume.clamp(0.0, 1.0));
      _naturalEndPauseApplied = false;
      _reachedEnd = false;
      // Swap: detach the old listener before reassigning _controller so that
      // _handlePlaybackProgress never sees a mismatched controller.
      final VideoPlayerController? old = _controller;
      old?.removeListener(_handlePlaybackProgress);
      _controller = newController;
      newController.addListener(_handlePlaybackProgress);
      await newController.play();
      if (mounted) setState(() {});
      if (old != null) await old.dispose();
    } catch (error) {
      _logger.severe("Failed to restart playback from $position: $error");
      await newController.dispose();
    }
  }

  Future<void> _enqueueSeek(Future<void> Function() work) {
    final Future<void> done = _seekTail.then((_) => work());
    _seekTail = done.catchError((Object _, StackTrace s) {});
    return done;
  }

  Future<void> _seekBy(Duration offset) => _enqueueSeek(() async {
    final VideoPlayerController? controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    _naturalEndPauseApplied = false;
    _reachedEnd = false;

    final Duration duration = controller.value.duration;
    final Duration clipStart = Duration(milliseconds: widget.startTimeMs);
    Duration next = controller.value.position + offset;
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
    _targetSeekPosition = next;
  });

  Future<void> _seekToStart() => _enqueueSeek(() async {
    final VideoPlayerController? controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    _naturalEndPauseApplied = false;
    _reachedEnd = false;
    final Duration target = Duration(milliseconds: widget.startTimeMs);
    await controller.seekTo(target);
    _targetSeekPosition = target;
  });

  Future<void> _seekToEnd() => _enqueueSeek(() async {
    final VideoPlayerController? controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    _naturalEndPauseApplied = false;
    _reachedEnd = false;
    final int? clipEndMs = widget.endTimeMs;
    if (clipEndMs != null) {
      await controller.seekTo(Duration(milliseconds: clipEndMs));
    } else {
      await controller.seekTo(controller.value.duration);
    }
    // At the clip/file end — play() should restart from clip start, not replay
    // from end, so clear the target rather than setting it to the end position.
    _targetSeekPosition = null;
  });

  @override
  void dispose() {
    widget.controller?._detach(this);
    unawaited(_disposeController());
    super.dispose();
  }

  Future<void> _disposeController() async {
    final VideoPlayerController? controller = _controller;
    controller?.removeListener(_handlePlaybackProgress);
    if (_lastIsPlaying) {
      _lastIsPlaying = false;
      widget.onPlayingChanged?.call(false);
    }
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
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints bc) {
                  final Size container = Size(bc.maxWidth, bc.maxHeight);
                  final Size intrinsic = controller.value.size;
                  final Rect videoRect = _videoDestinationRect(
                    container: container,
                    intrinsic: intrinsic,
                    fit: widget.videoBoxFit,
                  );
                  final bool showVideoOverlay = widget.videoAreaOverlay !=
                          null &&
                      videoRect.width > 0 &&
                      videoRect.height > 0;
                  return Stack(
                    fit: StackFit.expand,
                    clipBehavior: Clip.none,
                    children: <Widget>[
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: widget.clickTogglesPlayback
                            ? _togglePlayPause
                            : null,
                        child: Center(
                          child: FittedBox(
                            fit: widget.videoBoxFit,
                            child: SizedBox(
                              width: intrinsic.width,
                              height: intrinsic.height,
                              child: VideoPlayer(controller),
                            ),
                          ),
                        ),
                      ),
                      if (showVideoOverlay)
                        Positioned(
                          left: videoRect.left,
                          top: videoRect.top,
                          width: videoRect.width,
                          height: videoRect.height,
                          child: ClipRect(
                            child: widget.videoAreaOverlay!,
                          ),
                        ),
                    ],
                  );
                },
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
    final double horizontalPad = scaleDimension(context, 10);
    final double verticalPad = scaleDimension(context, 8);
    final double progressVerticalPad = scaleDimension(context, 4);
    final double controlsGap = scaleDimension(context, 8);
    return Container(
      color: Colors.black.withValues(alpha: 0.65),
      padding: EdgeInsets.fromLTRB(
        horizontalPad,
        verticalPad,
        horizontalPad,
        verticalPad,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          VideoProgressIndicator(
            controller,
            allowScrubbing: true,
            padding: EdgeInsets.symmetric(vertical: progressVerticalPad),
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
              SizedBox(width: controlsGap),
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

  static Rect _videoDestinationRect({
    required Size container,
    required Size intrinsic,
    required BoxFit fit,
  }) {
    if (intrinsic.width <= 0 ||
        intrinsic.height <= 0 ||
        container.width <= 0 ||
        container.height <= 0) {
      return Rect.zero;
    }
    final FittedSizes fs = applyBoxFit(fit, intrinsic, container);
    final Size d = fs.destination;
    final double left = (container.width - d.width) * 0.5;
    final double top = (container.height - d.height) * 0.5;
    return Rect.fromLTWH(left, top, d.width, d.height);
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
