import "package:flutter/material.dart";

/// Inclusive buffered range reported by a [ClipMediaPlayer] backend.
class ClipBufferedRange {
  const ClipBufferedRange({required this.start, required this.end});

  final Duration start;
  final Duration end;
}

/// Snapshot of playback used by [ClipPlayerView] and transport UI.
class ClipPlaybackState {
  const ClipPlaybackState({
    required this.isInitialized,
    required this.isPlaying,
    required this.isCompleted,
    required this.position,
    required this.duration,
    required this.size,
    this.buffered = const <ClipBufferedRange>[],
  });

  static const ClipPlaybackState uninitialized = ClipPlaybackState(
    isInitialized: false,
    isPlaying: false,
    isCompleted: false,
    position: Duration.zero,
    duration: Duration.zero,
    size: Size.zero,
  );

  final bool isInitialized;
  final bool isPlaying;
  final bool isCompleted;
  final Duration position;
  final Duration duration;
  final Size size;
  final List<ClipBufferedRange> buffered;

  ClipPlaybackState copyWith({
    bool? isInitialized,
    bool? isPlaying,
    bool? isCompleted,
    Duration? position,
    Duration? duration,
    Size? size,
    List<ClipBufferedRange>? buffered,
  }) {
    return ClipPlaybackState(
      isInitialized: isInitialized ?? this.isInitialized,
      isPlaying: isPlaying ?? this.isPlaying,
      isCompleted: isCompleted ?? this.isCompleted,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      size: size ?? this.size,
      buffered: buffered ?? this.buffered,
    );
  }
}
