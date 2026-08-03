import "dart:async";
import "dart:io";
import "dart:math" as math;

import "package:flutter/material.dart";
import "package:media_kit/media_kit.dart";
import "package:media_kit_video/media_kit_video.dart";

import "package:obs_clipshow/src/media_player/clip_media_player.dart";
import "package:obs_clipshow/src/media_player/clip_playback_state.dart";
import "package:obs_clipshow/src/osg/osg_models.dart";

/// libmpv-backed [media_kit] player.
class MediaKitClipMediaPlayer implements ClipMediaPlayer {
  MediaKitClipMediaPlayer({PlayoutOutputSize? textureCap})
    : _textureCap = textureCap ?? PlayoutOutputSize.fallback;

  final PlayoutOutputSize _textureCap;

  Player? _player;
  VideoController? _videoController;
  final StreamController<ClipPlaybackState> _states =
      StreamController<ClipPlaybackState>.broadcast();
  ClipPlaybackState _state = ClipPlaybackState.uninitialized;
  final List<StreamSubscription<dynamic>> _subs =
      <StreamSubscription<dynamic>>[];
  bool _opened = false;
  Timer? _emitThrottle;
  bool _emitPending = false;

  static const Duration _emitInterval = Duration(milliseconds: 50);

  @override
  Stream<ClipPlaybackState> get states => _states.stream;

  @override
  ClipPlaybackState get state => _state;

  void _scheduleEmit() {
    _emitPending = true;
    if (_emitThrottle?.isActive ?? false) {
      return;
    }
    _emitThrottle = Timer(_emitInterval, () {
      _emitThrottle = null;
      if (!_emitPending || _states.isClosed) {
        return;
      }
      _emitPending = false;
      _emitFromPlayer();
    });
  }

  void _emitImmediate() {
    _emitPending = false;
    _emitThrottle?.cancel();
    _emitThrottle = null;
    _emitFromPlayer();
  }

  void _emitFromPlayer() {
    final Player? p = _player;
    if (p == null || !_opened) {
      _state = ClipPlaybackState.uninitialized;
    } else {
      final Size size = p.state.width != null &&
              p.state.height != null &&
              p.state.width! > 0 &&
              p.state.height! > 0
          ? Size(p.state.width!.toDouble(), p.state.height!.toDouble())
          : (_state.size.width > 0 ? _state.size : const Size(16, 9));
      _state = ClipPlaybackState(
        isInitialized: true,
        isPlaying: p.state.playing,
        isCompleted: p.state.completed,
        position: p.state.position,
        duration: p.state.duration,
        size: size,
        // Skip demuxer buffer ranges — high-rate and unused for clip scrubbing.
        buffered: const <ClipBufferedRange>[],
      );
    }
    if (!_states.isClosed) {
      _states.add(_state);
    }
  }

  void _wireStreams(Player player) {
    for (final StreamSubscription<dynamic> s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
    // Position ticks are frequent (esp. 60fps); coalesce. Play/EOS/size need
    // prompt delivery for clip policy.
    _subs.addAll(<StreamSubscription<dynamic>>[
      player.stream.playing.listen((_) => _emitImmediate()),
      player.stream.completed.listen((_) => _emitImmediate()),
      player.stream.position.listen((_) => _scheduleEmit()),
      player.stream.duration.listen((_) => _emitImmediate()),
      player.stream.width.listen((_) => _emitImmediate()),
      player.stream.height.listen((_) => _emitImmediate()),
    ]);
  }

  String get _hwdec {
    if (Platform.isLinux) {
      // Prefer VAAPI on Linux (same default priority Clipshow uses for FVP).
      return "vaapi";
    }
    if (Platform.isWindows) {
      return "d3d11va";
    }
    if (Platform.isMacOS) {
      return "videotoolbox";
    }
    return "auto";
  }

  Future<void> _applyTextureCap(VideoController videoController, Player player) async {
    final int? srcW = player.state.width;
    final int? srcH = player.state.height;
    if (srcW == null || srcH == null || srcW <= 0 || srcH <= 0) {
      return;
    }
    final int maxW = _textureCap.width;
    final int maxH = _textureCap.height;
    if (srcW <= maxW && srcH <= maxH) {
      return;
    }
    final double scale = math.min(maxW / srcW, maxH / srcH);
    final int outW = math.max(1, (srcW * scale).round());
    final int outH = math.max(1, (srcH * scale).round());
    await videoController.setSize(width: outW, height: outH);
  }

  Future<void> _tuneNativePlayer(Player player) async {
    final PlatformPlayer? platform = player.platform;
    if (platform is! NativePlayer) {
      return;
    }
    // Allow dropping late frames rather than stalling audio/video sync on 60fps.
    await platform.setProperty("framedrop", "vo");
    await platform.setProperty("video-sync", "audio");
    await platform.setProperty("hwdec", _hwdec);
  }

  @override
  Future<void> openFile(String path) async {
    await _tearDownPlayer();
    final Player player = Player(
      configuration: const PlayerConfiguration(
        vo: "null",
        osc: false,
        bufferSize: 64 * 1024 * 1024,
      ),
    );
    final VideoController videoController = VideoController(
      player,
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration: true,
        hwdec: _hwdec,
      ),
    );
    _player = player;
    _videoController = videoController;
    _wireStreams(player);
    await _tuneNativePlayer(player);
    await player.open(Media(path), play: false);
    _opened = true;
    // Wait until texture path is ready, then optionally downscale to canvas.
    try {
      await videoController.waitUntilFirstFrameRendered.timeout(
        const Duration(seconds: 5),
      );
    } catch (_) {
      // Still usable; size may arrive later via stream.
    }
    await _applyTextureCap(videoController, player);
    _emitImmediate();
  }

  @override
  Future<void> play() async {
    final Player? p = _player;
    if (p == null || !_opened) {
      return;
    }
    await p.play();
  }

  @override
  Future<void> pause() async {
    final Player? p = _player;
    if (p == null || !_opened) {
      return;
    }
    await p.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    final Player? p = _player;
    if (p == null || !_opened) {
      return;
    }
    await p.seek(position);
    _emitImmediate();
  }

  @override
  Future<void> setVolume(double volume01) async {
    final Player? p = _player;
    if (p == null || !_opened) {
      return;
    }
    await p.setVolume(volume01.clamp(0.0, 1.0) * 100.0);
  }

  @override
  Widget buildView({required BoxFit fit}) {
    final VideoController? vc = _videoController;
    if (vc == null || !_opened) {
      return const SizedBox.shrink();
    }
    return Video(
      controller: vc,
      fit: fit,
      controls: NoVideoControls,
    );
  }

  Future<void> _tearDownPlayer() async {
    _opened = false;
    _emitPending = false;
    _emitThrottle?.cancel();
    _emitThrottle = null;
    for (final StreamSubscription<dynamic> s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    final Player? p = _player;
    _player = null;
    _videoController = null;
    if (p != null) {
      await p.dispose();
    }
    _emitFromPlayer();
  }

  @override
  Future<void> dispose() async {
    await _tearDownPlayer();
    await _states.close();
  }
}
