import "dart:convert";
import "dart:io";

import "package:path/path.dart" as p;

/// Sends a file to the OS trash / Recycle Bin (recoverable), without blocking on UI.
///
/// - **Linux:** tries `gio trash`, then `trash-put` (e.g. trash-cli package).
/// - **Windows:** PowerShell [FileSystem]::DeleteFile with SendToRecycleBin.
/// - **macOS:** Finder via `osascript` (moves file to Trash).
///
/// Throws [StateError] if no mechanism succeeds.
Future<void> moveFileToSystemTrash(String absolutePath) async {
  final String path = p.normalize(p.absolute(absolutePath));
  final File file = File(path);
  if (!await file.exists()) {
    throw FileSystemException("File not found", path);
  }

  if (Platform.isLinux) {
    ProcessResult r = await Process.run("gio", <String>["trash", path]);
    if (r.exitCode == 0) {
      return;
    }
    r = await Process.run("trash-put", <String>[path]);
    if (r.exitCode == 0) {
      return;
    }
    throw StateError(
      "Could not move file to trash. Tried `gio trash` and `trash-put`. "
      "Install `libglib2.0-bin` (gio) or `trash-cli`. "
      "Last stderr: ${_decode(r.stderr)}",
    );
  }

  if (Platform.isWindows) {
    final String escaped = path.replaceAll("'", "''");
    final ProcessResult r = await Process.run("powershell.exe", <String>[
      "-NoProfile",
      "-STA",
      "-Command",
      "Add-Type -AssemblyName Microsoft.VisualBasic; "
          "[Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile('$escaped', 'OnlyErrorDialogs', 'SendToRecycleBin')",
    ]);
    if (r.exitCode != 0) {
      throw StateError(
        "Could not send file to Recycle Bin: ${_decode(r.stderr)}${_decode(r.stdout)}",
      );
    }
    return;
  }

  if (Platform.isMacOS) {
    final String inner = _applescriptPathLiteral(path);
    final String script =
        'tell application "Finder" to delete POSIX file "$inner"';
    final ProcessResult r = await Process.run("/usr/bin/osascript", <String>[
      "-e",
      script,
    ]);
    if (r.exitCode != 0) {
      throw StateError(
        "Could not move file to Trash: ${_decode(r.stderr)}${_decode(r.stdout)}",
      );
    }
    return;
  }

  throw UnsupportedError(
    "System trash is not implemented for ${Platform.operatingSystem}.",
  );
}

/// Escapes [path] for use inside an AppleScript double-quoted string after `POSIX file`.
String _applescriptPathLiteral(String path) {
  return path.replaceAll(r"\", r"\\").replaceAll('"', r'\"');
}

String _decode(List<int>? bytes) {
  if (bytes == null || bytes.isEmpty) {
    return "";
  }
  return utf8.decode(bytes, allowMalformed: true);
}
