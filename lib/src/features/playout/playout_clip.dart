class PlayoutClip {
  const PlayoutClip({
    required this.filePath,
    required this.startTimeMs,
    required this.endTimeMs,
    this.initialPositionMs,
  });

  final String filePath;
  final int startTimeMs;
  final int? endTimeMs;
  final int? initialPositionMs;
}
