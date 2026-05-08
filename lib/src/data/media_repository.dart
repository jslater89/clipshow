import "package:sqflite/sqflite.dart";

import "../media/master_media_file.dart";
import "../media/media_clip.dart";
import "../media/media_list_item.dart";

class MediaRepository {
  MediaRepository(this._database);

  final Database _database;

  static const int _maxIssueDetailLength = 500;
  static const String masterTag = "Master";
  static const String clipTag = "Clip";

  /// Inserts or updates file stats. Preserves [media_issue] / [media_issue_detail] on conflict.
  Future<void> upsertMasterMedia({
    required String filePath,
    required String fileName,
    required int fileSizeBytes,
    required int modifiedAtMs,
    required int createdAtMs,
  }) async {
    await _database.transaction((Transaction txn) async {
      await txn.rawInsert(
        """
        INSERT INTO master_media_files (
          file_path, file_name, file_size_bytes, modified_at_ms, created_at_ms,
          media_issue, media_issue_detail
        ) VALUES (?, ?, ?, ?, ?, 'none', NULL)
        ON CONFLICT(file_path) DO UPDATE SET
          file_name = excluded.file_name,
          file_size_bytes = excluded.file_size_bytes,
          modified_at_ms = excluded.modified_at_ms,
          created_at_ms = excluded.created_at_ms
        """,
        <Object?>[filePath, fileName, fileSizeBytes, modifiedAtMs, createdAtMs],
      );
      final int? masterId = await _lookupMasterId(txn, filePath);
      if (masterId != null) {
        await _attachTagToMedia(
          txn,
          mediaType: MediaListItemType.master,
          mediaId: masterId,
          tag: masterTag,
        );
      }
    });
  }

  /// Sets stored issue (e.g. empty file or thumbnail / probe failure).
  Future<void> setMediaIssue(
    String filePath,
    MediaIssue issue, {
    String? detail,
  }) async {
    final String? storedDetail = _truncateDetail(detail);
    await _database.update(
      "master_media_files",
      <String, Object?>{
        "media_issue": issue.name,
        "media_issue_detail": storedDetail,
      },
      where: "file_path = ?",
      whereArgs: <Object?>[filePath],
    );
  }

  /// Clears [MediaIssue.unreadable] after a successful thumbnail (or pre-existing sidecar).
  /// Returns the number of rows updated (0 or 1).
  Future<int> clearUnreadableIssue(String filePath) async {
    return _database.rawUpdate(
      """
      UPDATE master_media_files
      SET media_issue = 'none', media_issue_detail = NULL
      WHERE file_path = ? AND media_issue = 'unreadable'
      """,
      <Object?>[filePath],
    );
  }

  /// Clears [MediaIssue.empty] when the file is no longer zero bytes.
  Future<void> clearEmptyIssue(String filePath) async {
    await _database.rawUpdate(
      """
      UPDATE master_media_files
      SET media_issue = 'none', media_issue_detail = NULL
      WHERE file_path = ? AND media_issue = 'empty'
      """,
      <Object?>[filePath],
    );
  }

  Future<void> deleteByPath(String filePath) async {
    await _database.transaction((Transaction txn) async {
      final int? masterId = await _lookupMasterId(txn, filePath);
      if (masterId != null) {
        await txn.delete(
          "media_tags",
          where: "media_type = ? AND media_id = ?",
          whereArgs: <Object?>["master", masterId],
        );
        await txn.delete(
          "media_tags",
          where:
              "media_type = ? AND media_id IN (SELECT id FROM clips WHERE master_media_id = ?)",
          whereArgs: <Object?>["clip", masterId],
        );
      }
      await txn.delete(
        "master_media_files",
        where: "file_path = ?",
        whereArgs: <Object?>[filePath],
      );
      await _deleteOrphanTags(txn);
    });
  }

  Future<List<MasterMediaFile>> listAll() async {
    final List<Map<String, Object?>> rows = await _database.query(
      "master_media_files",
      orderBy: "modified_at_ms DESC, file_name ASC",
    );
    return rows.map(MasterMediaFile.fromMap).toList();
  }

  Future<int> createClip({
    required int masterMediaId,
    required int inMs,
    required int? outMs,
  }) async {
    return _database.transaction((Transaction txn) async {
      final int clipId = await txn.insert("clips", <String, Object?>{
        "master_media_id": masterMediaId,
        "in_ms": inMs,
        "out_ms": outMs,
        "created_at_ms": DateTime.now().millisecondsSinceEpoch,
      });
      final List<Map<String, Object?>> inheritedTagRows = await txn.rawQuery(
        """
        SELECT tags.name
        FROM media_tags
        JOIN tags ON tags.id = media_tags.tag_id
        WHERE media_tags.media_type = 'master'
          AND media_tags.media_id = ?
          AND tags.name != ? COLLATE NOCASE
        """,
        <Object?>[masterMediaId, masterTag],
      );
      for (final Map<String, Object?> row in inheritedTagRows) {
        await _attachTagToMedia(
          txn,
          mediaType: MediaListItemType.clip,
          mediaId: clipId,
          tag: row["name"]! as String,
        );
      }
      await _attachTagToMedia(
        txn,
        mediaType: MediaListItemType.clip,
        mediaId: clipId,
        tag: clipTag,
      );
      return clipId;
    });
  }

  Future<List<MediaClip>> listClips() async {
    final List<Map<String, Object?>> rows = await _database.rawQuery("""
      SELECT
        clips.id,
        clips.master_media_id,
        clips.in_ms,
        clips.out_ms,
        clips.created_at_ms,
        master_media_files.file_path,
        master_media_files.file_name
      FROM clips
      JOIN master_media_files ON master_media_files.id = clips.master_media_id
      ORDER BY clips.created_at_ms DESC, clips.id DESC
      """);
    return rows.map(MediaClip.fromMap).toList();
  }

  Future<void> deleteClipById(int clipId) async {
    await _database.transaction((Transaction txn) async {
      await txn.delete(
        "media_tags",
        where: "media_type = ? AND media_id = ?",
        whereArgs: <Object?>["clip", clipId],
      );
      await txn.delete(
        "clips",
        where: "id = ?",
        whereArgs: <Object?>[clipId],
      );
      await _deleteOrphanTags(txn);
    });
  }

  Future<Set<String>> listTagsForMedia({
    required MediaListItemType mediaType,
    required int mediaId,
  }) async {
    final List<Map<String, Object?>> rows = await _database.rawQuery(
      """
      SELECT tags.name
      FROM media_tags
      JOIN tags ON tags.id = media_tags.tag_id
      WHERE media_tags.media_type = ? AND media_tags.media_id = ?
      ORDER BY tags.name COLLATE NOCASE ASC
      """,
      <Object?>[_mediaTypeValue(mediaType), mediaId],
    );
    return rows
        .map((Map<String, Object?> row) => row["name"]! as String)
        .toSet();
  }

  Future<Map<String, Set<String>>> listTagsForItems(
    List<MediaListItem> items,
  ) async {
    if (items.isEmpty) {
      return <String, Set<String>>{};
    }
    final String masterIds = items
        .where((MediaListItem item) => item.type == MediaListItemType.master)
        .map((MediaListItem item) => item.id)
        .join(",");
    final String clipIds = items
        .where((MediaListItem item) => item.type == MediaListItemType.clip)
        .map((MediaListItem item) => item.id)
        .join(",");
    final List<String> clauses = <String>[];
    if (masterIds.isNotEmpty) {
      clauses.add(
        "(media_tags.media_type = 'master' AND media_tags.media_id IN ($masterIds))",
      );
    }
    if (clipIds.isNotEmpty) {
      clauses.add(
        "(media_tags.media_type = 'clip' AND media_tags.media_id IN ($clipIds))",
      );
    }
    if (clauses.isEmpty) {
      return <String, Set<String>>{};
    }
    final List<Map<String, Object?>> rows = await _database.rawQuery("""
      SELECT media_tags.media_type, media_tags.media_id, tags.name
      FROM media_tags
      JOIN tags ON tags.id = media_tags.tag_id
      WHERE ${clauses.join(" OR ")}
      ORDER BY tags.name COLLATE NOCASE ASC
      """);
    final Map<String, Set<String>> tagsByKey = <String, Set<String>>{};
    for (final Map<String, Object?> row in rows) {
      final String mediaType = row["media_type"]! as String;
      final int mediaId = row["media_id"]! as int;
      final String tagName = row["name"]! as String;
      final String key = mediaType == "master" ? "m:$mediaId" : "c:$mediaId";
      tagsByKey.putIfAbsent(key, () => <String>{}).add(tagName);
    }
    return tagsByKey;
  }

  Future<List<String>> listAllTags() async {
    final List<Map<String, Object?>> rows = await _database.query(
      "tags",
      columns: <String>["name"],
      orderBy: "name COLLATE NOCASE ASC",
    );
    return rows
        .map((Map<String, Object?> row) => row["name"]! as String)
        .toList();
  }

  Future<List<String>> suggestTags(String query) async {
    final String normalized = normalizeTag(query);
    if (normalized.isEmpty) {
      return listAllTags();
    }
    final List<Map<String, Object?>> rows = await _database.query(
      "tags",
      columns: <String>["name"],
      where: "name LIKE ?",
      whereArgs: <Object?>["%$normalized%"],
      orderBy: "name COLLATE NOCASE ASC",
      limit: 20,
    );
    return rows
        .map((Map<String, Object?> row) => row["name"]! as String)
        .toList();
  }

  Future<void> addTagToMedia({
    required MediaListItemType mediaType,
    required int mediaId,
    required String tag,
  }) async {
    final String normalized = normalizeTag(tag);
    if (normalized.isEmpty) {
      return;
    }
    await _database.transaction((Transaction txn) async {
      await _attachTagToMedia(
        txn,
        mediaType: mediaType,
        mediaId: mediaId,
        tag: normalized,
      );
    });
  }

  Future<void> removeTagFromMedia({
    required MediaListItemType mediaType,
    required int mediaId,
    required String tag,
  }) async {
    final String normalized = normalizeTag(tag);
    if (normalized.isEmpty) {
      return;
    }
    await _database.transaction((Transaction txn) async {
      await txn.rawDelete(
        """
        DELETE FROM media_tags
        WHERE media_type = ?
          AND media_id = ?
          AND tag_id = (SELECT id FROM tags WHERE name = ? COLLATE NOCASE)
        """,
        <Object?>[_mediaTypeValue(mediaType), mediaId, normalized],
      );
      await _deleteOrphanTags(txn);
    });
  }

  Future<List<String>> listSavedTags() async {
    final List<Map<String, Object?>> rows = await _database.query(
      "saved_tags",
      columns: <String>["name"],
      orderBy: "name COLLATE NOCASE ASC",
    );
    return rows
        .map((Map<String, Object?> row) => row["name"]! as String)
        .toList();
  }

  Future<void> addSavedTag(String tag) async {
    final String normalized = normalizeTag(tag);
    if (normalized.isEmpty) {
      return;
    }
    await _database.insert("saved_tags", <String, Object?>{
      "name": normalized,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> removeSavedTag(String tag) async {
    final String normalized = normalizeTag(tag);
    if (normalized.isEmpty) {
      return;
    }
    await _database.delete(
      "saved_tags",
      where: "name = ? COLLATE NOCASE",
      whereArgs: <Object?>[normalized],
    );
  }

  Future<List<MediaListItem>> listMixedItems() async {
    final List<MasterMediaFile> masters = await listAll();
    final List<MediaClip> clips = await listClips();
    final List<MediaListItem> items = <MediaListItem>[
      ...masters.map(MediaListItem.master),
      ...clips.map(MediaListItem.clip),
    ];
    items.sort((MediaListItem a, MediaListItem b) {
      final int aTime = a.type == MediaListItemType.master
          ? a.master!.modifiedAtMs
          : a.clip!.createdAtMs;
      final int bTime = b.type == MediaListItemType.master
          ? b.master!.modifiedAtMs
          : b.clip!.createdAtMs;
      return bTime.compareTo(aTime);
    });
    return items;
  }

  Future<List<MediaListItem>> filterItems({
    required Set<String> requiredTags,
    required bool untaggedOnly,
  }) async {
    final List<MediaListItem> items = await listMixedItems();
    final Set<String> normalizedRequiredTags = requiredTags
        .map(normalizeTag)
        .where((String tag) => tag.isNotEmpty)
        .toSet();
    if (normalizedRequiredTags.isEmpty && !untaggedOnly) {
      return items;
    }

    final List<MediaListItem> visible = <MediaListItem>[];
    for (final MediaListItem item in items) {
      final Set<String> tags = await listTagsForMedia(
        mediaType: item.type,
        mediaId: item.id,
      );
      if (untaggedOnly && tags.isNotEmpty) {
        continue;
      }
      if (normalizedRequiredTags.isNotEmpty &&
          !normalizedRequiredTags.every(tags.contains)) {
        continue;
      }
      visible.add(item);
    }
    return visible;
  }

  String normalizeTag(String raw) {
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return "";
    }
    return trimmed.replaceAll(RegExp(r"\s+"), " ");
  }

  Future<int?> _lookupMasterId(
    DatabaseExecutor executor,
    String filePath,
  ) async {
    final List<Map<String, Object?>> rows = await executor.query(
      "master_media_files",
      columns: <String>["id"],
      where: "file_path = ?",
      whereArgs: <Object?>[filePath],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.single["id"]! as int;
  }

  Future<void> _attachTagToMedia(
    DatabaseExecutor executor, {
    required MediaListItemType mediaType,
    required int mediaId,
    required String tag,
  }) async {
    final String normalized = normalizeTag(tag);
    if (normalized.isEmpty) {
      return;
    }
    await executor.insert("tags", <String, Object?>{
      "name": normalized,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    final List<Map<String, Object?>> tagRows = await executor.query(
      "tags",
      columns: <String>["id"],
      where: "name = ? COLLATE NOCASE",
      whereArgs: <Object?>[normalized],
      limit: 1,
    );
    if (tagRows.isEmpty) {
      return;
    }
    final int tagId = tagRows.single["id"]! as int;
    await executor.insert("media_tags", <String, Object?>{
      "media_type": _mediaTypeValue(mediaType),
      "media_id": mediaId,
      "tag_id": tagId,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  String _mediaTypeValue(MediaListItemType mediaType) =>
      mediaType == MediaListItemType.master ? "master" : "clip";

  Future<void> _deleteOrphanTags(DatabaseExecutor executor) async {
    await executor.rawDelete("""
      DELETE FROM tags
      WHERE id NOT IN (SELECT DISTINCT tag_id FROM media_tags)
      """);
  }

  String? _truncateDetail(String? detail) {
    if (detail == null || detail.isEmpty) {
      return null;
    }
    if (detail.length <= _maxIssueDetailLength) {
      return detail;
    }
    return detail.substring(0, _maxIssueDetailLength);
  }
}
