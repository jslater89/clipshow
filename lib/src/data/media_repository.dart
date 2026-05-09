import "package:logging/logging.dart";
import "package:path/path.dart" as p;
import "package:sqflite/sqflite.dart";

import 'package:obs_clipshow/src/media/master_media_file.dart';
import 'package:obs_clipshow/src/media/media_clip.dart';
import 'package:obs_clipshow/src/media/media_list_item.dart';
import "package:obs_clipshow/src/workspace/workspace_media_paths.dart";
import "package:obs_clipshow/src/workspace/workspace_settings.dart";

class MediaRepository {
  MediaRepository(this._database);

  final Database _database;
  final Logger _logger = Logger("MediaRepository");

  static const int _maxIssueDetailLength = 500;
  static const String masterTag = "Master";
  static const String clipTag = "Clip";

  /// Inserts or updates file stats. Preserves [media_issue] / [media_issue_detail] on conflict.
  ///
  /// [filePath] must be workspace-relative (see [WorkspaceMediaPaths.storedMasterPath]).
  Future<void> upsertMasterMedia({
    required String filePath,
    required String fileName,
    required int fileSizeBytes,
    required int modifiedAtMs,
    required int createdAtMs,
    int? durationMs,
  }) async {
    await _database.transaction((Transaction txn) async {
      await txn.rawInsert(
        """
        INSERT INTO master_media_files (
          file_path, file_name, file_size_bytes, modified_at_ms, created_at_ms,
          duration_ms, media_issue, media_issue_detail
        ) VALUES (?, ?, ?, ?, ?, ?, 'none', NULL)
        ON CONFLICT(file_path) DO UPDATE SET
          file_name = excluded.file_name,
          file_size_bytes = excluded.file_size_bytes,
          modified_at_ms = excluded.modified_at_ms,
          created_at_ms = excluded.created_at_ms,
          duration_ms = excluded.duration_ms
        """,
        <Object?>[
          filePath,
          fileName,
          fileSizeBytes,
          modifiedAtMs,
          createdAtMs,
          durationMs,
        ],
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

  /// Rewrites legacy absolute [master_media_files.file_path] values to paths
  /// relative to [workspaceRoot] (forward slashes, portable across machines).
  Future<void> migrateMasterPathsToWorkspaceRelative(String workspaceRoot) async {
    final String ws = p.normalize(p.absolute(workspaceRoot));
    final List<Map<String, Object?>> rows = await _database.query(
      "master_media_files",
      columns: <String>["id", "file_path"],
    );
    _logger.info(
      "Migrating master_media_files.file_path rows to workspace-relative "
      "(workspace: $ws, rows: ${rows.length}).",
    );
    int convertedFromAbsolute = 0;
    int normalizedRelativeOnly = 0;
    int skippedOutsideWorkspace = 0;
    int skippedEmpty = 0;
    int unchanged = 0;
    for (final Map<String, Object?> row in rows) {
      final int id = row["id"]! as int;
      final String raw = row["file_path"]! as String;
      final String trimmed = raw.trim();
      if (trimmed.isEmpty) {
        skippedEmpty++;
        continue;
      }
      if (!p.isAbsolute(trimmed)) {
        final String normalized = WorkspaceMediaPaths.normalizeStored(trimmed);
        if (normalized != raw) {
          _logger.fine(
            "Master id=$id: normalize stored relative path "
            "\"$raw\" → \"$normalized\"",
          );
          await _database.update(
            "master_media_files",
            <String, Object?>{"file_path": normalized},
            where: "id = ?",
            whereArgs: <Object?>[id],
          );
          normalizedRelativeOnly++;
        } else {
          unchanged++;
        }
        continue;
      }
      final String abs = p.normalize(trimmed);
      final String rel = p.relative(abs, from: ws);
      if (rel.startsWith("..")) {
        skippedOutsideWorkspace++;
        _logger.warning(
          "Master id=$id: skip path outside workspace (file_path: \"$raw\").",
        );
        continue;
      }
      final String stored = WorkspaceMediaPaths.normalizeStored(rel);
      if (stored == raw) {
        unchanged++;
        continue;
      }
      _logger.fine(
        "Master id=$id: absolute → workspace-relative \"$raw\" → \"$stored\"",
      );
      await _database.update(
        "master_media_files",
        <String, Object?>{"file_path": stored},
        where: "id = ?",
        whereArgs: <Object?>[id],
      );
      convertedFromAbsolute++;
    }
    _logger.info(
      "Master path migration finished: "
      "$convertedFromAbsolute absolute→relative, "
      "$normalizedRelativeOnly slash-normalized, "
      "$unchanged already portable, "
      "$skippedOutsideWorkspace skipped (outside workspace), "
      "$skippedEmpty empty path.",
    );
  }

  Future<MasterMediaFile?> getMasterByPath(String filePath) async {
    final List<Map<String, Object?>> rows = await _database.query(
      "master_media_files",
      where: "file_path = ?",
      whereArgs: <Object?>[filePath],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return MasterMediaFile.fromMap(rows.single);
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
        clips.display_name_override,
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
      await txn.delete("clips", where: "id = ?", whereArgs: <Object?>[clipId]);
      await _deleteOrphanTags(txn);
    });
  }

  Future<void> updateClipRange({
    required int clipId,
    required int inMs,
    required int? outMs,
  }) async {
    await _database.update(
      "clips",
      <String, Object?>{"in_ms": inMs, "out_ms": outMs},
      where: "id = ?",
      whereArgs: <Object?>[clipId],
    );
  }

  Future<void> setDisplayNameOverride({
    required MediaListItemType mediaType,
    required int mediaId,
    required String? displayNameOverride,
  }) async {
    final String? normalized = _normalizeDisplayNameOverride(
      displayNameOverride,
    );
    if (mediaType == MediaListItemType.master) {
      await _database.update(
        "master_media_files",
        <String, Object?>{"display_name_override": normalized},
        where: "id = ?",
        whereArgs: <Object?>[mediaId],
      );
      return;
    }
    await _database.update(
      "clips",
      <String, Object?>{"display_name_override": normalized},
      where: "id = ?",
      whereArgs: <Object?>[mediaId],
    );
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

  Future<void> addTagsToItems({
    required List<MediaListItem> items,
    required List<String> tags,
  }) async {
    if (items.isEmpty || tags.isEmpty) {
      return;
    }
    final List<String> normalizedTags = tags
        .map(normalizeTag)
        .where((String tag) => tag.isNotEmpty)
        .toSet()
        .toList();
    if (normalizedTags.isEmpty) {
      return;
    }
    await _database.transaction((Transaction txn) async {
      for (final MediaListItem item in items) {
        for (final String tag in normalizedTags) {
          await _attachTagToMedia(
            txn,
            mediaType: item.type,
            mediaId: item.id,
            tag: tag,
          );
        }
      }
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

  Future<WorkspaceSettingsBundle> loadWorkspaceSettings() async {
    final TelestratorDefaults telestratorDefaults =
        await _loadTelestratorDefaults();
    final DecoderConfig decoderConfig = await _loadDecoderConfig();
    final MdkLogVerbosity mdkLogVerbosity = await _loadMdkLogVerbosity();
    final ObsSceneSwitchConfig? obsConfig = await _loadObsSceneSwitchConfig();
    final List<WebhookSceneSwitchConfig> webhooks =
        await _loadWebhookSceneSwitchConfigs();
    final List<String> ignoredFolders = await listIgnoredFolders();
    final CapturePathsSettings capturePaths = await _loadCapturePathsSettings();
    return WorkspaceSettingsBundle(
      telestratorDefaults: telestratorDefaults,
      decoderConfig: decoderConfig,
      mdkLogVerbosity: mdkLogVerbosity,
      obsSceneSwitchConfig: obsConfig,
      webhookSceneSwitchConfigs: webhooks,
      ignoredFolders: ignoredFolders,
      capturePathsSettings: capturePaths,
    );
  }

  Future<CapturePathsSettings> _loadCapturePathsSettings() async {
    final String recording =
        (await _getWorkspaceSetting("capture.recordingRelativeDir"))?.trim() ??
        CapturePathsSettings.defaultRecordingRelativeDir;
    final String output =
        (await _getWorkspaceSetting("capture.outputRelativeDir"))?.trim() ?? "";
    return CapturePathsSettings(
      recordingRelativeDir: recording.isEmpty
          ? CapturePathsSettings.defaultRecordingRelativeDir
          : recording,
      outputRelativeDir: output,
    );
  }

  Future<void> saveCapturePathsSettings(CapturePathsSettings value) async {
    final String recording = value.recordingRelativeDir.trim().isEmpty
        ? CapturePathsSettings.defaultRecordingRelativeDir
        : value.recordingRelativeDir.trim();
    await _putWorkspaceSetting("capture.recordingRelativeDir", recording);
    await _putWorkspaceSetting(
      "capture.outputRelativeDir",
      value.outputRelativeDir.trim(),
    );
    await ensureRecordingRelativeDirIgnored(recording);
  }

  /// Ensures [relativePath] is listed under ignored folders when non-empty (workspace-relative).
  Future<void> ensureRecordingRelativeDirIgnored(String relativePath) async {
    final String normalized = _normalizeRelativeDir(relativePath);
    if (normalized.isEmpty) {
      return;
    }
    await addIgnoredFolder(normalized);
  }

  String _normalizeRelativeDir(String raw) {
    String path = raw.trim().replaceAll("\\", "/");
    while (path.startsWith("/")) {
      path = path.substring(1);
    }
    return path;
  }

  Future<MasterMediaFile?> getMasterByFilePath(
    String path,
    String workspaceRoot,
  ) async {
    final String stored = WorkspaceMediaPaths.storedMasterPath(
      workspaceRoot,
      p.normalize(p.absolute(path)),
    );
    final List<Map<String, Object?>> rows = await _database.query(
      "master_media_files",
      where: "file_path = ?",
      whereArgs: <Object?>[stored],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return MasterMediaFile.fromMap(rows.single);
  }

  Future<TelestratorDefaults> _loadTelestratorDefaults() async {
    final TelestratorDefaults fallback = TelestratorDefaults.fallback();
    final int colorOneArgb =
        int.tryParse(
          await _getWorkspaceSetting("telestrator.color1") ??
              fallback.colorOneArgb.toString(),
        ) ??
        fallback.colorOneArgb;
    final int colorTwoArgb =
        int.tryParse(
          await _getWorkspaceSetting("telestrator.color2") ??
              fallback.colorTwoArgb.toString(),
        ) ??
        fallback.colorTwoArgb;
    final int colorThreeArgb =
        int.tryParse(
          await _getWorkspaceSetting("telestrator.color3") ??
              fallback.colorThreeArgb.toString(),
        ) ??
        fallback.colorThreeArgb;
    final double brushSize =
        double.tryParse(
          await _getWorkspaceSetting("telestrator.brushSize") ??
              fallback.brushSize.toString(),
        ) ??
        fallback.brushSize;
    final bool enabledByDefault =
        (await _getWorkspaceSetting("telestrator.enabledByDefault")) == "true"
        ? true
        : fallback.enabledByDefault;
    return TelestratorDefaults(
      colorOneArgb: colorOneArgb,
      colorTwoArgb: colorTwoArgb,
      colorThreeArgb: colorThreeArgb,
      brushSize: brushSize,
      enabledByDefault: enabledByDefault,
    );
  }

  Future<void> saveTelestratorDefaults(TelestratorDefaults value) async {
    await _putWorkspaceSetting(
      "telestrator.color1",
      value.colorOneArgb.toString(),
    );
    await _putWorkspaceSetting(
      "telestrator.color2",
      value.colorTwoArgb.toString(),
    );
    await _putWorkspaceSetting(
      "telestrator.color3",
      value.colorThreeArgb.toString(),
    );
    await _putWorkspaceSetting(
      "telestrator.brushSize",
      value.brushSize.toString(),
    );
    await _putWorkspaceSetting(
      "telestrator.enabledByDefault",
      value.enabledByDefault.toString(),
    );
  }

  Future<DecoderConfig> _loadDecoderConfig() async {
    final String? storedList = await _getWorkspaceSetting(
      "decoder.enabledProfiles",
    );
    if (storedList != null && storedList.trim().isNotEmpty) {
      final List<DecoderProfile> parsed = storedList
          .split(",")
          .map((String raw) => raw.trim())
          .where((String raw) => raw.isNotEmpty)
          .map(
            (String name) => DecoderProfile.values.firstWhere(
              (DecoderProfile item) => item.name == name,
              orElse: () => DecoderProfile.vaapi,
            ),
          )
          .toList();
      if (parsed.isNotEmpty) {
        return DecoderConfig(enabledProfiles: parsed);
      }
    }
    final String stored =
        await _getWorkspaceSetting("decoder.profile") ?? "vaapi";
    final DecoderProfile profile = DecoderProfile.values.firstWhere(
      (DecoderProfile item) => item.name == stored,
      orElse: () => DecoderProfile.vaapi,
    );
    return DecoderConfig(enabledProfiles: <DecoderProfile>[profile]);
  }

  Future<void> saveDecoderConfig(DecoderConfig value) async {
    final List<DecoderProfile> normalized = value.enabledProfiles.isEmpty
        ? <DecoderProfile>[DecoderProfile.vaapi]
        : value.enabledProfiles;
    await _putWorkspaceSetting(
      "decoder.enabledProfiles",
      normalized.map((DecoderProfile item) => item.name).join(","),
    );
    await _putWorkspaceSetting("decoder.profile", normalized.first.name);
  }

  Future<MdkLogVerbosity> _loadMdkLogVerbosity() async {
    final String stored =
        await _getWorkspaceSetting("mdk.logVerbosity") ?? "warning";
    return MdkLogVerbosity.values.firstWhere(
      (MdkLogVerbosity item) => item.name == stored,
      orElse: () => MdkLogVerbosity.warning,
    );
  }

  Future<void> saveMdkLogVerbosity(MdkLogVerbosity value) async {
    await _putWorkspaceSetting("mdk.logVerbosity", value.name);
  }

  Future<ObsSceneSwitchConfig?> _loadObsSceneSwitchConfig() async {
    final List<Map<String, Object?>> rows = await _database.query(
      "scene_switch_profiles",
      where: "profile_type = ?",
      whereArgs: <Object?>["obs"],
      orderBy: "id DESC",
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    final Map<String, Object?> row = rows.single;
    return ObsSceneSwitchConfig(
      enabled: (row["enabled"] as int? ?? 1) == 1,
      serverAddress: (row["obs_server_address"] as String?) ?? "127.0.0.1",
      port: (row["obs_port"] as int?) ?? 4455,
      password: (row["obs_password"] as String?) ?? "",
      videoScene: (row["obs_video_scene"] as String?) ?? "Video Scene",
      faceScene: (row["obs_face_scene"] as String?) ?? "Face Scene",
      captureScene: (row["obs_capture_scene"] as String?) ?? "",
    );
  }

  Future<void> saveObsSceneSwitchConfig(ObsSceneSwitchConfig? value) async {
    await _database.transaction((Transaction txn) async {
      if (value == null) {
        await txn.delete(
          "scene_switch_profiles",
          where: "profile_type = ?",
          whereArgs: <Object?>["obs"],
        );
        return;
      }
      final List<Map<String, Object?>> existing = await txn.query(
        "scene_switch_profiles",
        columns: <String>["id"],
        where: "profile_type = ?",
        whereArgs: <Object?>["obs"],
        limit: 1,
      );
      final Map<String, Object?> payload = <String, Object?>{
        "profile_type": "obs",
        "name": "OBS",
        "enabled": value.enabled ? 1 : 0,
        "obs_server_address": value.serverAddress,
        "obs_port": value.port,
        "obs_password": value.password,
        "obs_video_scene": value.videoScene,
        "obs_face_scene": value.faceScene,
        "obs_capture_scene": value.captureScene,
      };
      if (existing.isEmpty) {
        await txn.insert("scene_switch_profiles", payload);
      } else {
        await txn.update(
          "scene_switch_profiles",
          payload,
          where: "id = ?",
          whereArgs: <Object?>[existing.single["id"]],
        );
      }
    });
  }

  Future<List<WebhookSceneSwitchConfig>>
  _loadWebhookSceneSwitchConfigs() async {
    final List<Map<String, Object?>> rows = await _database.query(
      "scene_switch_profiles",
      where: "profile_type = ?",
      whereArgs: <Object?>["webhook"],
      orderBy: "id ASC",
    );
    return rows.map((Map<String, Object?> row) {
      return WebhookSceneSwitchConfig(
        id: row["id"]! as int,
        name: (row["name"] as String?) ?? "Webhook",
        enabled: (row["enabled"] as int? ?? 1) == 1,
        url: (row["webhook_url"] as String?) ?? "",
        method:
            ((row["webhook_method"] as String?) ?? "POST").toUpperCase() ==
                "GET"
            ? WebhookMethod.get
            : WebhookMethod.post,
        getQueryParamName:
            (row["webhook_get_query_param"] as String?) ?? "scene",
        postBodyType:
            ((row["webhook_post_body_type"] as String?) ?? "json")
                    .toLowerCase() ==
                "form"
            ? WebhookPostBodyType.form
            : WebhookPostBodyType.json,
        sceneKey: (row["webhook_scene_key"] as String?) ?? "scene",
      );
    }).toList();
  }

  Future<int> addWebhookSceneSwitchConfig(
    WebhookSceneSwitchConfig value,
  ) async {
    return _database.insert("scene_switch_profiles", <String, Object?>{
      "profile_type": "webhook",
      "name": value.name,
      "enabled": value.enabled ? 1 : 0,
      "webhook_url": value.url,
      "webhook_method": value.method == WebhookMethod.get ? "GET" : "POST",
      "webhook_get_query_param": value.getQueryParamName,
      "webhook_post_body_type": value.postBodyType == WebhookPostBodyType.form
          ? "form"
          : "json",
      "webhook_scene_key": value.sceneKey,
    });
  }

  Future<void> updateWebhookSceneSwitchConfig(
    WebhookSceneSwitchConfig value,
  ) async {
    await _database.update(
      "scene_switch_profiles",
      <String, Object?>{
        "name": value.name,
        "enabled": value.enabled ? 1 : 0,
        "webhook_url": value.url,
        "webhook_method": value.method == WebhookMethod.get ? "GET" : "POST",
        "webhook_get_query_param": value.getQueryParamName,
        "webhook_post_body_type": value.postBodyType == WebhookPostBodyType.form
            ? "form"
            : "json",
        "webhook_scene_key": value.sceneKey,
      },
      where: "id = ? AND profile_type = ?",
      whereArgs: <Object?>[value.id, "webhook"],
    );
  }

  Future<void> deleteWebhookSceneSwitchConfig(int id) async {
    await _database.delete(
      "scene_switch_profiles",
      where: "id = ? AND profile_type = ?",
      whereArgs: <Object?>[id, "webhook"],
    );
  }

  Future<void> setObsSceneSwitchEnabled(bool enabled) async {
    await _database.update(
      "scene_switch_profiles",
      <String, Object?>{"enabled": enabled ? 1 : 0},
      where: "profile_type = ?",
      whereArgs: <Object?>["obs"],
    );
  }

  Future<void> setWebhookSceneSwitchEnabled(int id, bool enabled) async {
    await _database.update(
      "scene_switch_profiles",
      <String, Object?>{"enabled": enabled ? 1 : 0},
      where: "id = ? AND profile_type = ?",
      whereArgs: <Object?>[id, "webhook"],
    );
  }

  Future<List<String>> listIgnoredFolders() async {
    final List<Map<String, Object?>> rows = await _database.query(
      "ignored_folders",
      columns: <String>["relative_path"],
      orderBy: "relative_path ASC",
    );
    return rows
        .map((Map<String, Object?> row) => row["relative_path"]! as String)
        .toList();
  }

  Future<void> addIgnoredFolder(String relativePath) async {
    final String normalized = normalizeTag(relativePath).replaceAll("\\", "/");
    if (normalized.isEmpty) {
      return;
    }
    await _database.insert("ignored_folders", <String, Object?>{
      "relative_path": normalized,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> removeIgnoredFolder(String relativePath) async {
    await _database.delete(
      "ignored_folders",
      where: "relative_path = ?",
      whereArgs: <Object?>[relativePath],
    );
  }

  Future<String?> _getWorkspaceSetting(String key) async {
    final List<Map<String, Object?>> rows = await _database.query(
      "workspace_settings",
      columns: <String>["value"],
      where: "key = ?",
      whereArgs: <Object?>[key],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.single["value"]! as String;
  }

  Future<void> _putWorkspaceSetting(String key, String value) async {
    await _database.insert("workspace_settings", <String, Object?>{
      "key": key,
      "value": value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
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

  String? _normalizeDisplayNameOverride(String? raw) {
    if (raw == null) {
      return null;
    }
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
