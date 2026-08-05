import "dart:async";
import "dart:math" as math;

import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:logging/logging.dart";

import "package:obs_clipshow/src/app/ui_scale.dart";
import "package:obs_clipshow/src/media_player/clip_media_player.dart";
import "package:obs_clipshow/src/media_player/clip_media_player_factory.dart";
import "package:obs_clipshow/src/media_player/clip_playback_state.dart";

class ClipPlayerController {
  _ClipPlayerViewState? _state;

  Future<void> togglePlayPause() async {
    await _state?._togglePlayPause();
  }

  Future<void> pause() async {
    await _state?._pauseOnly();
  }

  Future<void> play() async {
    await _state?._playOnly();
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

  Future<void> seekTo(Duration position) async {
    await _state?._seekToClamped(position);
  }

  /// Playback snapshot for external transport UI (Manage preview bar).
  ValueNotifier<ClipPlaybackState>? get playbackListenable =>
      _state?._playbackNotifier;

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
    this.canvasAreaOverlay,
    this.onPositionChanged,
    this.onPlayingChanged,
    this.controller,
    this.videoBoxFit = BoxFit.contain,
    this.volume = 1.0,
    this.beforeVideoInitialize,
    this.onFirstFrameReady,
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

  /// Drawn over the full playout canvas (the layout container), including
  /// letterbox/pillarbox gutters. OSG and telestrator use normalized 0..1
  /// coordinates relative to this area.
  final Widget? canvasAreaOverlay;
  final ValueChanged<int>? onPositionChanged;
  final ValueChanged<bool>? onPlayingChanged;
  final ClipPlayerController? controller;

  /// How the decoded video is fitted inside the player (e.g. [BoxFit.contain] vs [BoxFit.cover]).
  final BoxFit videoBoxFit;

  /// When non-null, awaited at the start of each video controller init (after
  /// dispose). Used e.g. to stagger dashboard preview init after playout teardown.
  final Future<void> Function()? beforeVideoInitialize;

  /// Called once per successful init after the first video frame is scheduled
  /// to paint (post-frame). Also invoked on init failure so callers are not
  /// blocked indefinitely.
  final VoidCallback? onFirstFrameReady;

  /// Audio volume in the range 0.0–1.0. Applied on init and whenever it changes
  /// (without reinitializing the underlying player).
  final double volume;

  @override
  State<ClipPlayerView> createState() => _ClipPlayerViewState();
}

class _ClipPlayerViewState extends State<ClipPlayerView> {
  final Logger _logger = Logger("ClipPlayerView");
  ClipMediaPlayer? _player;
  StreamSubscription<ClipPlaybackState>? _stateSub;
  final ValueNotifier<ClipPlaybackState> _playbackNotifier =
      ValueNotifier<ClipPlaybackState>(ClipPlaybackState.uninitialized);
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
  /// EOS/stopped state on completion. In that state, seeks may update the
  /// Dart-side position but the platform ignores them. When play is subsequently
  /// called the engine may restart from position 0 regardless of any pre-play
  /// seek.
  ///
  /// The fix is to reopen a fresh player at the desired position (see
  /// [_reopenPlayerAt]).
  bool _reachedEnd = false;

  /// Paused on the last frame of the file (no clip end mark) so we avoid the
  /// platform EOS/stopped state where seeks are ignored until the player is
  /// recreated ([_reopenPlayerAt]).
  bool _naturalEndPauseApplied = false;
  bool _firstFrameReadyNotified = false;
  bool _playbackDisposed = false;

  /// Stable video surface widget — rebuilt only when the player instance or fit changes.
  Widget? _videoView;

  /// Last video size used for letterboxing; drives rare [setState] for layout.
  Size _layoutSize = Size.zero;
  bool _layoutInitialized = false;

  DateTime? _lastTransportNotify;
  static const Duration _transportNotifyMinInterval = Duration(
    milliseconds: 50,
  );

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
      unawaited(_reinitializeController(reason: "didUpdateWidget"));
    } else if (oldWidget.volume != widget.volume) {
      final ClipMediaPlayer? player = _player;
      if (player != null && player.state.isInitialized) {
        unawaited(player.setVolume(widget.volume.clamp(0.0, 1.0)));
      }
    } else if (oldWidget.videoBoxFit != widget.videoBoxFit) {
      _rebuildVideoView();
      if (mounted) {
        setState(() {});
      }
    }
  }

  void _rebuildVideoView() {
    final ClipMediaPlayer? player = _player;
    if (player == null || !player.state.isInitialized) {
      _videoView = null;
      return;
    }
    _videoView = player.buildView(fit: widget.videoBoxFit);
  }

  Future<void> _reinitializeController({required String reason}) async {
    _logger.info("Reinitializing controller due to $reason");
    _targetSeekPosition = null;
    _reachedEnd = false;
    _naturalEndPauseApplied = false;
    _firstFrameReadyNotified = false;
    _videoView = null;
    _layoutSize = Size.zero;
    _layoutInitialized = false;
    await _disposePlayer();
    await _initializePlayer();
  }

  void _notifyFirstFrameReady() {
    if (_firstFrameReadyNotified) {
      return;
    }
    _firstFrameReadyNotified = true;
    widget.onFirstFrameReady?.call();
  }

  void _scheduleFirstFrameReadyAfterPaint() {
    if (_firstFrameReadyNotified) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _firstFrameReadyNotified) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _notifyFirstFrameReady();
      });
    });
  }

  Future<void> _initializePlayer() async {
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
      final ClipMediaPlayer player = ClipMediaPlayerFactory.create();
      _player = player;
      _stateSub = player.states.listen(_handlePlaybackProgress);
      await player.openFile(widget.filePath);
      if (!mounted) {
        await _disposePlayer();
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
      await player.seek(initialPosition);
      if (!mounted) {
        await _disposePlayer();
        return;
      }
      await player.setVolume(widget.volume.clamp(0.0, 1.0));
      if (widget.autoPlay) {
        await player.play();
      }
      if (mounted) {
        _layoutInitialized = player.state.isInitialized;
        _layoutSize = player.state.size;
        _rebuildVideoView();
        setState(() {});
        _scheduleFirstFrameReadyAfterPaint();
      }
    } catch (error, stackTrace) {
      _logger.severe(
        "Failed to initialize player for ${widget.filePath}: $error",
        error,
        stackTrace,
      );
      if (mounted) {
        setState(() {
          _errorMessage = "Unable to load selected media.";
        });
        _notifyFirstFrameReady();
      }
    }
  }

  void _handlePlaybackProgress(ClipPlaybackState state) {
    // Transport bar listens via [_playbackNotifier]; do not setState on every
    // position tick — that rebuilds the video surface and causes stutter.
    // Also throttle notifier updates (~20 Hz) so 60fps sources don't rebuild
    // the scrubber every decoder tick — but always publish position/play/EOS
    // changes so Home/seek after completion cannot leave a stale scrub bar.
    _publishTransport(state);
    if (!state.isInitialized) {
      return;
    }

    if (state.isCompleted) {
      _reachedEnd = true;
    }

    final int currentMs = state.position.inMilliseconds;
    final ClipMediaPlayer? player = _player;
    if (player == null) {
      return;
    }
    if (currentMs < widget.startTimeMs) {
      unawaited(player.seek(Duration(milliseconds: widget.startTimeMs)));
    }

    final int? endMs = widget.endTimeMs;
    if (endMs != null) {
      if (currentMs > endMs) {
        if (state.isPlaying) {
          unawaited(player.pause());
        }
        unawaited(player.seek(Duration(milliseconds: endMs)));
      }
    } else {
      // Full file or open-ended clip: pause on the last frame *before* the
      // decoder latches to EOS, same idea as marking out on a bounded clip.
      final Duration duration = state.duration;
      if (duration > Duration.zero && !_naturalEndPauseApplied) {
        final Duration position = state.position;
        Duration lead = _naturalEndPauseLead;
        if (duration <= lead) {
          lead = Duration.zero;
        }
        final Duration threshold = duration - lead;
        final bool shouldFreeze =
            state.isCompleted || (state.isPlaying && position >= threshold);
        if (shouldFreeze) {
          _naturalEndPauseApplied = true;
          unawaited(_freezeOnNaturalEnd(duration));
        }
      }
    }
    widget.onPositionChanged?.call(state.position.inMilliseconds);
    final bool isPlaying = state.isPlaying;
    if (isPlaying != _lastIsPlaying) {
      _lastIsPlaying = isPlaying;
      widget.onPlayingChanged?.call(isPlaying);
    }

    final bool layoutChanged =
        !_layoutInitialized ||
        state.size.width != _layoutSize.width ||
        state.size.height != _layoutSize.height;
    if (layoutChanged && mounted) {
      _layoutInitialized = true;
      _layoutSize = state.size;
      _rebuildVideoView();
      setState(() {});
    }
  }

  void _publishTransport(ClipPlaybackState state, {bool force = false}) {
    if (_playbackDisposed) {
      return;
    }
    final ClipPlaybackState previous = _playbackNotifier.value;
    final bool playingChanged = state.isPlaying != previous.isPlaying;
    final bool positionChanged = state.position != previous.position;
    final bool completedChanged = state.isCompleted != previous.isCompleted;
    final DateTime now = DateTime.now();
    final bool due =
        _lastTransportNotify == null ||
        now.difference(_lastTransportNotify!) >= _transportNotifyMinInterval;
    if (force ||
        playingChanged ||
        positionChanged ||
        completedChanged ||
        state.isCompleted ||
        !state.isInitialized ||
        due) {
      _playbackNotifier.value = state;
      _lastTransportNotify = now;
    }
  }

  Future<void> _freezeOnNaturalEnd(Duration duration) async {
    final ClipMediaPlayer? player = _player;
    if (player == null || !player.state.isInitialized) {
      return;
    }
    try {
      if (player.state.isPlaying) {
        await player.pause();
      }
      await player.seek(duration);
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
    final ClipMediaPlayer? player = _player;
    if (player == null || !player.state.isInitialized) {
      return;
    }
    if (player.state.isPlaying) {
      await player.pause();
      return;
    }

    await _enqueueSeek(() async {});

    final bool hadReachedEnd = _reachedEnd;
    _reachedEnd = false;
    final Duration? target = _targetSeekPosition;
    _targetSeekPosition = null;

    if (hadReachedEnd) {
      // After EOS the underlying engine may be in a stopped state where seeks
      // are unreliable and play() restarts from the beginning. Reopen a fresh
      // player at the desired position while the old one still displays.
      final Duration playFrom =
          target ?? Duration(milliseconds: widget.startTimeMs);
      await _reopenPlayerAt(playFrom, play: true);
    } else {
      await player.play();
    }
  }

  Future<void> _pauseOnly() async {
    final ClipMediaPlayer? player = _player;
    if (player == null || !player.state.isInitialized || !player.state.isPlaying) {
      return;
    }
    await player.pause();
  }

  Future<void> _playOnly() async {
    await _togglePlayPause();
  }

  /// Opens a new [ClipMediaPlayer] for the same file at [position], swaps it in
  /// while the old player is still displaying (no black flash), then optionally
  /// plays. Used after EOS where platform seeks are ignored.
  Future<void> _reopenPlayerAt(
    Duration position, {
    required bool play,
  }) async {
    final ClipMediaPlayer newPlayer = ClipMediaPlayerFactory.create();
    try {
      await newPlayer.openFile(widget.filePath);
      if (!mounted) {
        await newPlayer.dispose();
        return;
      }
      await newPlayer.seek(position);
      if (!mounted) {
        await newPlayer.dispose();
        return;
      }
      await newPlayer.setVolume(widget.volume.clamp(0.0, 1.0));
      _naturalEndPauseApplied = false;
      _reachedEnd = false;
      final ClipMediaPlayer? old = _player;
      final StreamSubscription<ClipPlaybackState>? oldSub = _stateSub;
      await oldSub?.cancel();
      _player = newPlayer;
      _stateSub = newPlayer.states.listen(_handlePlaybackProgress);
      _handlePlaybackProgress(newPlayer.state);
      // Force transport to the reopen target even if the backend briefly
      // reports the previous completed position.
      _publishTransport(
        newPlayer.state.copyWith(
          position: position,
          isCompleted: false,
          isPlaying: false,
        ),
        force: true,
      );
      if (play) {
        await newPlayer.play();
      }
      if (mounted) {
        _layoutInitialized = newPlayer.state.isInitialized;
        _layoutSize = newPlayer.state.size;
        _rebuildVideoView();
        setState(() {});
      }
      if (old != null) {
        await old.dispose();
      }
    } catch (error, stackTrace) {
      _logger.severe(
        "Failed to reopen playback at $position: $error",
        error,
        stackTrace,
      );
      await newPlayer.dispose();
    }
  }

  Future<void> _enqueueSeek(Future<void> Function() work) {
    final Future<void> done = _seekTail.then((_) => work());
    _seekTail = done.catchError((Object _, StackTrace s) {});
    return done;
  }

  Duration _clampSeekPosition(Duration position, ClipPlaybackState state) {
    final Duration clipStart = Duration(milliseconds: widget.startTimeMs);
    Duration next = position;
    if (next < clipStart) {
      next = clipStart;
    }

    final int? endMs = widget.endTimeMs;
    if (endMs != null) {
      final Duration clipEnd = Duration(milliseconds: endMs);
      if (next > clipEnd) {
        next = clipEnd;
      }
    } else {
      final Duration duration = state.duration;
      if (duration > Duration.zero && next > duration) {
        next = duration;
      }
    }
    return next;
  }

  /// After hard EOS, seeks are ignored by FVP; reopen at [target] instead.
  Future<void> _seekOrReopenAfterEos(Duration target) async {
    final ClipMediaPlayer? player = _player;
    if (player == null || !player.state.isInitialized) {
      return;
    }
    final bool needsReopen = _reachedEnd || player.state.isCompleted;
    _naturalEndPauseApplied = false;
    _reachedEnd = false;
    if (needsReopen) {
      await _reopenPlayerAt(target, play: false);
    } else {
      await player.seek(target);
      final ClipPlaybackState after = player.state;
      // Optimistic scrubber update when the backend is slow to emit the new
      // position (or still reports the prior frame).
      if (after.position != target || after.isCompleted) {
        _publishTransport(
          after.copyWith(position: target, isCompleted: false),
          force: true,
        );
      } else {
        _publishTransport(after, force: true);
      }
    }
    _targetSeekPosition = target;
  }

  Future<void> _seekToClamped(Duration position) => _enqueueSeek(() async {
    final ClipMediaPlayer? player = _player;
    if (player == null || !player.state.isInitialized) {
      return;
    }
    final Duration next = _clampSeekPosition(position, player.state);
    await _seekOrReopenAfterEos(next);
  });

  Future<void> _seekBy(Duration offset) => _enqueueSeek(() async {
    final ClipMediaPlayer? player = _player;
    if (player == null || !player.state.isInitialized) {
      return;
    }
    final Duration next = _clampSeekPosition(
      player.state.position + offset,
      player.state,
    );
    await _seekOrReopenAfterEos(next);
  });

  Future<void> _seekToStart() => _enqueueSeek(() async {
    final ClipMediaPlayer? player = _player;
    if (player == null || !player.state.isInitialized) {
      return;
    }
    final Duration target = Duration(milliseconds: widget.startTimeMs);
    await _seekOrReopenAfterEos(target);
  });

  Future<void> _seekToEnd() => _enqueueSeek(() async {
    final ClipMediaPlayer? player = _player;
    if (player == null || !player.state.isInitialized) {
      return;
    }
    final int? clipEndMs = widget.endTimeMs;
    final Duration target = clipEndMs != null
        ? Duration(milliseconds: clipEndMs)
        : player.state.duration;
    if (target <= Duration.zero && clipEndMs == null) {
      return;
    }
    await _seekOrReopenAfterEos(target);
    // At the clip/file end — play() should restart from clip start, not replay
    // from end, so clear the target rather than setting it to the end position.
    _targetSeekPosition = null;
  });

  @override
  void dispose() {
    _playbackDisposed = true;
    widget.controller?._detach(this);
    unawaited(_disposePlayer());
    _playbackNotifier.dispose();
    super.dispose();
  }

  Future<void> _disposePlayer() async {
    final StreamSubscription<ClipPlaybackState>? sub = _stateSub;
    _stateSub = null;
    await sub?.cancel();
    if (_lastIsPlaying) {
      _lastIsPlaying = false;
      widget.onPlayingChanged?.call(false);
    }
    final ClipMediaPlayer? player = _player;
    _player = null;
    _videoView = null;
    if (player != null) {
      await player.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(autofocus: true, child: _buildBody());
  }

  Widget _buildBody() {
    final ClipMediaPlayer? player = _player;
    final ClipPlaybackState state =
        player?.state ?? ClipPlaybackState.uninitialized;
    if (_errorMessage != null) {
      return Center(
        child: Text(
          _errorMessage!,
          style: const TextStyle(color: Colors.white),
        ),
      );
    }
    if (player == null || !state.isInitialized || _videoView == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final Size intrinsic = _layoutSize.width > 0 ? _layoutSize : state.size;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Column(
          children: <Widget>[
            Expanded(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints bc) {
                  final Size container = Size(bc.maxWidth, bc.maxHeight);
                  final Rect videoRect = _videoDestinationRect(
                    container: container,
                    intrinsic: intrinsic,
                    fit: widget.videoBoxFit,
                  );
                  final bool hasVideoRect =
                      videoRect.width > 0 && videoRect.height > 0;
                  if (!hasVideoRect) {
                    return const SizedBox.shrink();
                  }
                  return Stack(
                    fit: StackFit.expand,
                    clipBehavior: Clip.none,
                    children: <Widget>[
                      Positioned.fromRect(
                        rect: videoRect,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: widget.clickTogglesPlayback
                              ? _togglePlayPause
                              : null,
                          child: _videoView,
                        ),
                      ),
                      if (widget.canvasAreaOverlay != null)
                        Positioned.fill(child: widget.canvasAreaOverlay!),
                    ],
                  );
                },
              ),
            ),
            if (widget.showControls) _buildControls(),
          ],
        ),
        if (widget.overlay != null) widget.overlay!,
      ],
    );
  }

  Widget _buildControls() {
    return ClipPlayerTransportBar(
      playbackListenable: _playbackNotifier,
      startTimeMs: widget.startTimeMs,
      endTimeMs: widget.endTimeMs,
      seekStep: widget.seekStep,
      onTogglePlayPause: _togglePlayPause,
      onSeekBy: _seekBy,
      onScrub: _seekToClamped,
      onPauseForScrub: () async {
        final ClipMediaPlayer? player = _player;
        if (player != null && player.state.isPlaying) {
          await player.pause();
        }
      },
      onResumeAfterScrub: () async {
        await _playOnly();
      },
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
}

/// Transport controls for [ClipPlayerView]; may sit below a canvas-framed preview.
class ClipPlayerTransportBar extends StatelessWidget {
  const ClipPlayerTransportBar({
    super.key,
    required this.playbackListenable,
    required this.startTimeMs,
    required this.endTimeMs,
    required this.onTogglePlayPause,
    required this.onSeekBy,
    required this.onScrub,
    required this.onPauseForScrub,
    required this.onResumeAfterScrub,
    this.seekStep = const Duration(seconds: 5),
  });

  final ValueListenable<ClipPlaybackState> playbackListenable;
  final int startTimeMs;
  final int? endTimeMs;
  final Future<void> Function() onTogglePlayPause;
  final Future<void> Function(Duration offset) onSeekBy;
  final Future<void> Function(Duration position) onScrub;
  final Future<void> Function() onPauseForScrub;
  final Future<void> Function() onResumeAfterScrub;
  final Duration seekStep;

  @override
  Widget build(BuildContext context) {
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
      child: ValueListenableBuilder<ClipPlaybackState>(
        valueListenable: playbackListenable,
        builder: (BuildContext context, ClipPlaybackState state, Widget? child) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _ClipBoundedProgressIndicator(
                playbackListenable: playbackListenable,
                startTimeMs: startTimeMs,
                endTimeMs: endTimeMs,
                allowScrubbing: true,
                padding: EdgeInsets.symmetric(vertical: progressVerticalPad),
                onScrub: onScrub,
                onPauseForScrub: onPauseForScrub,
                onResumeAfterScrub: onResumeAfterScrub,
              ),
              Row(
                children: <Widget>[
                  IconButton(
                    tooltip: "Back 5 Seconds",
                    onPressed: () => onSeekBy(-seekStep),
                    icon: const Icon(Icons.replay_5),
                    color: Colors.white,
                  ),
                  IconButton(
                    tooltip: state.isPlaying ? "Pause" : "Play",
                    onPressed: onTogglePlayPause,
                    icon: Icon(
                      state.isPlaying ? Icons.pause : Icons.play_arrow,
                    ),
                    color: Colors.white,
                  ),
                  IconButton(
                    tooltip: "Forward 5 Seconds",
                    onPressed: () => onSeekBy(seekStep),
                    icon: const Icon(Icons.forward_5),
                    color: Colors.white,
                  ),
                  SizedBox(width: controlsGap),
                  Expanded(
                    child: Text(
                      "${formatClipPlayerDuration(state.position)} / "
                      "${formatClipPlayerDuration(state.duration)}",
                      style: const TextStyle(color: Colors.white),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

String formatClipPlayerDuration(Duration duration) {
  final int totalSeconds = duration.inSeconds;
  final int hours = totalSeconds ~/ 3600;
  final int minutes = (totalSeconds % 3600) ~/ 60;
  final int seconds = totalSeconds % 60;
  if (hours > 0) {
    return "$hours:${minutes.toString().padLeft(2, "0")}:${seconds.toString().padLeft(2, "0")}";
  }
  return "${minutes.toString().padLeft(2, "0")}:${seconds.toString().padLeft(2, "0")}";
}

/// Progress bar scoped to clip in/out when bounds are set; otherwise full file.
class _ClipBoundedProgressIndicator extends StatefulWidget {
  const _ClipBoundedProgressIndicator({
    required this.playbackListenable,
    required this.startTimeMs,
    required this.endTimeMs,
    required this.allowScrubbing,
    required this.padding,
    required this.onScrub,
    required this.onPauseForScrub,
    required this.onResumeAfterScrub,
  });

  final ValueListenable<ClipPlaybackState> playbackListenable;
  final int startTimeMs;
  final int? endTimeMs;
  final bool allowScrubbing;
  final EdgeInsets padding;
  final Future<void> Function(Duration position) onScrub;
  final Future<void> Function() onPauseForScrub;
  final Future<void> Function() onResumeAfterScrub;

  bool get _hasClipBounds => startTimeMs > 0 || endTimeMs != null;

  @override
  State<_ClipBoundedProgressIndicator> createState() =>
      _ClipBoundedProgressIndicatorState();
}

class _ClipBoundedProgressIndicatorState
    extends State<_ClipBoundedProgressIndicator> {
  bool _controllerWasPlaying = false;

  ClipPlaybackState get _state => widget.playbackListenable.value;

  void _handleUpdate() {
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    widget.playbackListenable.addListener(_handleUpdate);
  }

  @override
  void didUpdateWidget(covariant _ClipBoundedProgressIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playbackListenable != widget.playbackListenable) {
      oldWidget.playbackListenable.removeListener(_handleUpdate);
      widget.playbackListenable.addListener(_handleUpdate);
    }
  }

  @override
  void dispose() {
    widget.playbackListenable.removeListener(_handleUpdate);
    super.dispose();
  }

  int _clipEndMs() {
    final int? endMs = widget.endTimeMs;
    if (endMs != null) {
      return endMs;
    }
    return _state.duration.inMilliseconds;
  }

  int _clipSpanMs() {
    return math.max(0, _clipEndMs() - widget.startTimeMs);
  }

  double _playedFraction() {
    if (!_state.isInitialized) {
      return 0;
    }
    if (!widget._hasClipBounds) {
      final int durationMs = _state.duration.inMilliseconds;
      if (durationMs <= 0) {
        return 0;
      }
      return _state.position.inMilliseconds / durationMs;
    }
    final int spanMs = _clipSpanMs();
    if (spanMs <= 0) {
      return 0;
    }
    final int relativeMs = _state.position.inMilliseconds - widget.startTimeMs;
    return (relativeMs / spanMs).clamp(0.0, 1.0);
  }

  double _bufferedFraction() {
    if (!_state.isInitialized) {
      return 0;
    }
    final int durationMs = _state.duration.inMilliseconds;
    if (durationMs <= 0) {
      return 0;
    }
    final int maxBufferedMs = _state.buffered
        .map((ClipBufferedRange range) => range.end.inMilliseconds)
        .fold(0, math.max);
    if (!widget._hasClipBounds) {
      return maxBufferedMs / durationMs;
    }
    final int spanMs = _clipSpanMs();
    if (spanMs <= 0) {
      return 0;
    }
    final int relativeBufferedMs = maxBufferedMs - widget.startTimeMs;
    return (relativeBufferedMs / spanMs).clamp(0.0, 1.0);
  }

  Future<void> _seekToRelative(double relative) async {
    if (!_state.isInitialized) {
      return;
    }
    final Duration target;
    if (!widget._hasClipBounds) {
      target = _state.duration * relative.clamp(0.0, 1.0);
    } else {
      final int spanMs = _clipSpanMs();
      final int targetMs =
          widget.startTimeMs + (relative.clamp(0.0, 1.0) * spanMs).round();
      target = Duration(milliseconds: targetMs);
    }
    await widget.onScrub(target);
  }

  @override
  Widget build(BuildContext context) {
    const Color playedColor = Color.fromRGBO(255, 0, 0, 0.7);
    const Color bufferedColor = Color.fromRGBO(50, 50, 200, 0.2);
    const Color backgroundColor = Color.fromRGBO(200, 200, 200, 0.5);
    final Widget progressIndicator;
    if (_state.isInitialized) {
      progressIndicator = Stack(
        fit: StackFit.passthrough,
        children: <Widget>[
          LinearProgressIndicator(
            value: _bufferedFraction(),
            valueColor: const AlwaysStoppedAnimation<Color>(bufferedColor),
            backgroundColor: backgroundColor,
          ),
          LinearProgressIndicator(
            value: _playedFraction(),
            valueColor: const AlwaysStoppedAnimation<Color>(playedColor),
            backgroundColor: Colors.transparent,
          ),
        ],
      );
    } else {
      progressIndicator = const LinearProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(playedColor),
        backgroundColor: backgroundColor,
      );
    }

    final Widget paddedProgressIndicator = Padding(
      padding: widget.padding,
      child: progressIndicator,
    );

    if (!widget.allowScrubbing) {
      return paddedProgressIndicator;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      child: paddedProgressIndicator,
      onHorizontalDragStart: (DragStartDetails details) {
        if (!_state.isInitialized) {
          return;
        }
        _controllerWasPlaying = _state.isPlaying;
        if (_controllerWasPlaying) {
          unawaited(widget.onPauseForScrub());
        }
      },
      onHorizontalDragUpdate: (DragUpdateDetails details) {
        if (!_state.isInitialized) {
          return;
        }
        final RenderBox box = context.findRenderObject()! as RenderBox;
        final Offset tapPos = box.globalToLocal(details.globalPosition);
        final double relative = tapPos.dx / box.size.width;
        unawaited(_seekToRelative(relative));
      },
      onHorizontalDragEnd: (DragEndDetails details) {
        if (_controllerWasPlaying &&
            _state.position != _state.duration) {
          unawaited(widget.onResumeAfterScrub());
        }
      },
      onTapDown: (TapDownDetails details) {
        if (!_state.isInitialized) {
          return;
        }
        final RenderBox box = context.findRenderObject()! as RenderBox;
        final Offset tapPos = box.globalToLocal(details.globalPosition);
        final double relative = tapPos.dx / box.size.width;
        unawaited(_seekToRelative(relative));
      },
    );
  }
}
