import "dart:async";
import "dart:io";

import "package:flutter/material.dart";
import "package:video_player/video_player.dart";

import "package:obs_clipshow/src/media_player/clip_media_player.dart";
import "package:obs_clipshow/src/media_player/clip_playback_state.dart";

/// [video_player] + fvp backend.
class FvpClipMediaPlayer implements ClipMediaPlayer {
  VideoPlayerController? _controller;
  final StreamController<ClipPlaybackState> _states =
      StreamController<ClipPlaybackState>.broadcast();
  ClipPlaybackState _state = ClipPlaybackState.uninitialized;

  @override
  Stream<ClipPlaybackState> get states => _states.stream;

  @override
  ClipPlaybackState get state => _state;

  void _emit() {
    final VideoPlayerController? c = _controller;
    final ClipPlaybackState next;
    if (c == null || !c.value.isInitialized) {
      next = ClipPlaybackState.uninitialized;
    } else {
      final VideoPlayerValue v = c.value;
      next = ClipPlaybackState(
        isInitialized: true,
        isPlaying: v.isPlaying,
        isCompleted: v.isCompleted,
        position: v.position,
        duration: v.duration,
        size: v.size,
        buffered: v.buffered
            .map(
              (DurationRange r) =>
                  ClipBufferedRange(start: r.start, end: r.end),
            )
            .toList(growable: false),
      );
    }
    // Skip duplicate ticks (common when the controller notifies for non-UI reasons).
    if (_state.isInitialized == next.isInitialized &&
        _state.isPlaying == next.isPlaying &&
        _state.isCompleted == next.isCompleted &&
        _state.position == next.position &&
        _state.duration == next.duration &&
        _state.size == next.size) {
      return;
    }
    _state = next;
    if (!_states.isClosed) {
      _states.add(_state);
    }
  }

  void _onControllerTick() => _emit();

  @override
  Future<void> openFile(String path) async {
    await _disposeControllerOnly();
    final VideoPlayerController controller = VideoPlayerController.file(
      File(path),
    );
    _controller = controller;
    await controller.initialize();
    controller.addListener(_onControllerTick);
    _emit();
  }

  @override
  Future<void> play() async {
    final VideoPlayerController? c = _controller;
    if (c == null || !c.value.isInitialized) {
      return;
    }
    await c.play();
  }

  @override
  Future<void> pause() async {
    final VideoPlayerController? c = _controller;
    if (c == null || !c.value.isInitialized) {
      return;
    }
    await c.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    final VideoPlayerController? c = _controller;
    if (c == null || !c.value.isInitialized) {
      return;
    }
    await c.seekTo(position);
  }

  @override
  Future<void> setVolume(double volume01) async {
    final VideoPlayerController? c = _controller;
    if (c == null || !c.value.isInitialized) {
      return;
    }
    await c.setVolume(volume01.clamp(0.0, 1.0));
  }

  @override
  Widget buildView({required BoxFit fit}) {
    final VideoPlayerController? c = _controller;
    if (c == null || !c.value.isInitialized) {
      return const SizedBox.shrink();
    }
    // Fit is applied by ClipPlayerView's letterbox layout; fill the allocated
    // rect here.
    return VideoPlayer(c);
  }

  Future<void> _disposeControllerOnly() async {
    final VideoPlayerController? c = _controller;
    if (c == null) {
      return;
    }
    c.removeListener(_onControllerTick);
    _controller = null;
    await c.dispose();
    _emit();
  }

  @override
  Future<void> dispose() async {
    await _disposeControllerOnly();
    await _states.close();
  }
}
