import "dart:convert";
import "dart:io";

import "package:path/path.dart" as p;
import "package:path_provider/path_provider.dart";

class WorkspacePreferences {
  Future<String?> loadWorkspacePath() async {
    final File file = await _preferencesFile();
    if (!await file.exists()) {
      return null;
    }
    final String rawJson = await file.readAsString();
    if (rawJson.trim().isEmpty) {
      return null;
    }

    final Map<String, dynamic> payload =
        jsonDecode(rawJson) as Map<String, dynamic>;
    return payload["workspacePath"] as String?;
  }

  Future<void> saveWorkspacePath(String? workspacePath) async {
    final File file = await _preferencesFile();
    if (workspacePath == null || workspacePath.isEmpty) {
      if (await file.exists()) {
        await file.delete();
      }
      return;
    }
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode(<String, String>{"workspacePath": workspacePath}),
    );
  }

  Future<File> _preferencesFile() async {
    final Directory supportDirectory = await getApplicationSupportDirectory();
    return File(
      p.join(supportDirectory.path, "obs_clipshow", "workspace_prefs.json"),
    );
  }
}
