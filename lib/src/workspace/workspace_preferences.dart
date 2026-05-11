import "dart:convert";
import "dart:io";

import "package:path/path.dart" as p;
import "package:path_provider/path_provider.dart";

/// Application preferences stored alongside workspace discovery state (JSON file).
///
/// Includes last workspace path and global UI scale — independent of workspace DB settings.
class WorkspacePreferences {
  static const String _keyWorkspacePath = "workspacePath";
  static const String _keyUiScale = "uiScale";

  Future<String?> loadWorkspacePath() async {
    final Map<String, dynamic> payload = await _loadPayloadOrEmpty();
    final Object? path = payload[_keyWorkspacePath];
    if (path is String && path.isNotEmpty) {
      return path;
    }
    return null;
  }

  Future<void> saveWorkspacePath(String? workspacePath) async {
    final Map<String, dynamic> payload = await _loadPayloadOrEmpty();
    if (workspacePath == null || workspacePath.isEmpty) {
      payload.remove(_keyWorkspacePath);
    } else {
      payload[_keyWorkspacePath] = workspacePath;
    }
    await _writePayload(payload);
  }

  /// Persisted UI zoom factor (matches app text/layout scaling).
  Future<double?> loadUiScale() async {
    final Map<String, dynamic> payload = await _loadPayloadOrEmpty();
    final Object? raw = payload[_keyUiScale];
    if (raw is num) {
      return raw.toDouble();
    }
    return null;
  }

  Future<void> saveUiScale(double scale) async {
    final Map<String, dynamic> payload = await _loadPayloadOrEmpty();
    payload[_keyUiScale] = scale;
    await _writePayload(payload);
  }

  Future<Map<String, dynamic>> _loadPayloadOrEmpty() async {
    final File file = await _preferencesFile();
    if (!await file.exists()) {
      return <String, dynamic>{};
    }
    final String rawJson = await file.readAsString();
    if (rawJson.trim().isEmpty) {
      return <String, dynamic>{};
    }
    final Object? decoded = jsonDecode(rawJson);
    if (decoded is Map<String, dynamic>) {
      return Map<String, dynamic>.from(decoded);
    }
    return <String, dynamic>{};
  }

  Future<void> _writePayload(Map<String, dynamic> payload) async {
    final File file = await _preferencesFile();
    if (payload.isEmpty) {
      if (await file.exists()) {
        await file.delete();
      }
      return;
    }
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(payload));
  }

  Future<File> _preferencesFile() async {
    final Directory supportDirectory = await getApplicationSupportDirectory();
    return File(
      p.join(supportDirectory.path, "obs_clipshow", "workspace_prefs.json"),
    );
  }
}
