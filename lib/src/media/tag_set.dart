class TagSet {
  const TagSet({
    required this.id,
    required this.name,
    this.annotations,
    required this.createdAtMs,
  });

  final int id;
  final String name;
  final String? annotations;
  final int createdAtMs;

  factory TagSet.fromMap(Map<String, Object?> map) {
    return TagSet(
      id: map["id"]! as int,
      name: map["name"]! as String,
      annotations: map["annotations"] as String?,
      createdAtMs: map["created_at_ms"]! as int,
    );
  }
}
