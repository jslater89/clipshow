import "package:flutter/widgets.dart";

import "package:obs_clipshow/src/media_player/clip_playback_state.dart";

/// Narrow local-file playback surface for Manage preview and Playout.
///
/// Clip in/out policy, seek queues, and EOS restart live in [ClipPlayerView];
/// backends only open/decode/render and report [ClipPlaybackState].
abstract class ClipMediaPlayer {
  Stream<ClipPlaybackState> get states;

  ClipPlaybackState get state;

  Future<void> openFile(String path);

  Future<void> play();

  Future<void> pause();

  Future<void> seek(Duration position);

  /// Volume in Clipshow range 0.0–1.0; adapters map to native scales.
  Future<void> setVolume(double volume01);

  Future<void> dispose();

  /// Backend-owned video surface (e.g. [VideoPlayer] or media_kit [Video]).
  Widget buildView({required BoxFit fit});
}
