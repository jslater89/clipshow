class PlayoutClip {
  const PlayoutClip({
    required this.filePath,
    required this.startTimeMs,
    required this.endTimeMs,
  });

  final String filePath;
  final int startTimeMs;
  final int? endTimeMs;
}
