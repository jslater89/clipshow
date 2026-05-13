import "dart:convert";
import "dart:io";
import "dart:typed_data";

import "package:archive/archive.dart";
import "package:path/path.dart" as p;

import "package:obs_clipshow/src/osg/osg_models.dart";
import "package:obs_clipshow/src/workspace/workspace_media_paths.dart";

/// JSON array of five [OsgPreset] maps (same encoding as workspace storage).
const String osgPresetPackPresetsEntry = "osg_presets.json";

/// Image files live under this prefix; path after prefix matches stored
/// [OsgPreset.templateRelativePath] (forward slashes).
const String osgPresetPackAssetsPrefix = "assets/";

String _zipNormPath(String name) => name.replaceAll("\\", "/");

ArchiveFile? _findFile(Archive archive, String posixPath) {
  final String want = _zipNormPath(posixPath);
  for (final ArchiveFile f in archive.files) {
    if (f.isFile && _zipNormPath(f.name) == want) {
      return f;
    }
  }
  return null;
}

/// Collects workspace-relative image paths referenced by [config].
Set<String> osgPresetPackReferencedImagePaths(OsgWorkspaceConfig config) {
  final Set<String> out = <String>{};
  for (final OsgPreset pr in config.workspacePresets) {
    if (pr.templateBackgroundKind != OsgTemplateBackgroundKind.image) {
      continue;
    }
    final String rel = pr.templateRelativePath.trim();
    if (rel.isEmpty) {
      continue;
    }
    out.add(WorkspaceMediaPaths.normalizeStored(rel));
  }
  return out;
}

/// Builds a ZIP: [osgPresetPackPresetsEntry] plus [osgPresetPackAssetsPrefix]&lt;rel&gt; for each image.
Uint8List buildOsgPresetPackZip({
  required String workspaceRoot,
  required OsgWorkspaceConfig config,
}) {
  final String root = workspaceRoot.trim();
  final Archive archive = Archive();
  archive.add(
    ArchiveFile.string(
      osgPresetPackPresetsEntry,
      config.encodeToStorageJson(),
    ),
  );
  for (final String rel in osgPresetPackReferencedImagePaths(config)) {
    final String zipPath = "$osgPresetPackAssetsPrefix$rel";
    try {
      final String abs = WorkspaceMediaPaths.absoluteMasterPath(root, rel);
      final File f = File(abs);
      if (!f.existsSync()) {
        continue;
      }
      final Uint8List bytes = f.readAsBytesSync();
      archive.add(ArchiveFile.bytes(zipPath, bytes));
    } on ArgumentError {
      continue;
    }
  }
  return ZipEncoder().encodeBytes(archive);
}

/// Result of [importOsgPresetPackFromZipBytes].
class OsgPresetPackImportResult {
  const OsgPresetPackImportResult({
    required this.ok,
    required this.config,
    this.warnings = const <String>[],
  });

  /// False when the archive cannot be read or [osgPresetPackPresetsEntry] is missing.
  final bool ok;

  /// Only meaningful when [ok] is true.
  final OsgWorkspaceConfig config;

  final List<String> warnings;
}

/// Reads [osgPresetPackPresetsEntry], copies assets into [workspaceRoot]/osg/pack_import_&lt;stamp&gt;/,
/// and returns a new [OsgWorkspaceConfig] with updated template paths.
Future<OsgPresetPackImportResult> importOsgPresetPackFromZipBytes({
  required String workspaceRoot,
  required Uint8List zipBytes,
}) async {
  final String root = workspaceRoot.trim();
  final List<String> warnings = <String>[];
  if (root.isEmpty) {
    return OsgPresetPackImportResult(
      ok: false,
      config: OsgWorkspaceConfig.fallback(),
      warnings: const <String>["Workspace root is empty."],
    );
  }
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(zipBytes);
  } on Object catch (e) {
    return OsgPresetPackImportResult(
      ok: false,
      config: OsgWorkspaceConfig.fallback(),
      warnings: <String>["Could not read ZIP: $e"],
    );
  }
  final ArchiveFile? jsonFile = _findFile(archive, osgPresetPackPresetsEntry);
  if (jsonFile == null) {
    return OsgPresetPackImportResult(
      ok: false,
      config: OsgWorkspaceConfig.fallback(),
      warnings: const <String>[
        "Missing $osgPresetPackPresetsEntry in archive.",
      ],
    );
  }
  final String jsonRaw = utf8.decode(jsonFile.readBytes() ?? Uint8List(0));
  if (jsonRaw.trim().isEmpty) {
    return OsgPresetPackImportResult(
      ok: false,
      config: OsgWorkspaceConfig.fallback(),
      warnings: const <String>["Empty $osgPresetPackPresetsEntry."],
    );
  }
  Object? decoded;
  try {
    decoded = jsonDecode(jsonRaw);
  } on Object catch (e) {
    return OsgPresetPackImportResult(
      ok: false,
      config: OsgWorkspaceConfig.fallback(),
      warnings: <String>["Invalid JSON: $e"],
    );
  }
  if (decoded is! List<dynamic> || decoded.isEmpty) {
    return OsgPresetPackImportResult(
      ok: false,
      config: OsgWorkspaceConfig.fallback(),
      warnings: const <String>["Presets JSON must be a non-empty array."],
    );
  }
  final OsgWorkspaceConfig parsed = OsgWorkspaceConfig.decodeFromStorageJson(
    jsonRaw,
  );

  final String stamp = _importStamp();
  final String importDirRel = WorkspaceMediaPaths.normalizeStored(
    p.join("osg", "pack_import_$stamp"),
  );
  final Directory importDir = Directory(
    WorkspaceMediaPaths.absoluteMasterPath(root, importDirRel),
  );
  await importDir.create(recursive: true);

  final Map<String, String> reloc = <String, String>{};
  int fileCounter = 0;

  Future<void> relocateOne(String storedRel) async {
    if (reloc.containsKey(storedRel)) {
      return;
    }
    final String zipPath = "$osgPresetPackAssetsPrefix$storedRel";
    final ArchiveFile? asset = _findFile(archive, zipPath);
    if (asset == null) {
      warnings.add("Missing asset in ZIP: $zipPath");
      return;
    }
    final Uint8List? data = asset.readBytes();
    if (data == null || data.isEmpty) {
      warnings.add("Empty asset in ZIP: $zipPath");
      return;
    }
    final String base = p.basename(storedRel.replaceAll("\\", "/"));
    final String safeBase = base.trim().isEmpty ? "image.bin" : base;
    fileCounter += 1;
    final String destRel = WorkspaceMediaPaths.normalizeStored(
      p.join(importDirRel, "${fileCounter}_$safeBase"),
    );
    final String destAbs = WorkspaceMediaPaths.absoluteMasterPath(root, destRel);
    final File out = File(destAbs);
    await out.parent.create(recursive: true);
    await out.writeAsBytes(data, flush: true);
    reloc[storedRel] = destRel;
  }

  for (final String rel in osgPresetPackReferencedImagePaths(parsed)) {
    await relocateOne(rel);
  }

  final List<OsgPreset> next = parsed.workspacePresets
      .map((OsgPreset pr) {
        if (pr.templateBackgroundKind != OsgTemplateBackgroundKind.image) {
          return pr;
        }
        final String rel = WorkspaceMediaPaths.normalizeStored(
          pr.templateRelativePath.trim(),
        );
        if (rel.isEmpty) {
          return pr;
        }
        final String? to = reloc[rel];
        if (to == null) {
          return pr;
        }
        return pr.copyWith(templateRelativePath: to);
      })
      .toList();

  return OsgPresetPackImportResult(
    ok: true,
    config: OsgWorkspaceConfig(presets: next),
    warnings: warnings,
  );
}

String _importStamp() {
  final DateTime n = DateTime.now().toUtc();
  String two(int v) => v.toString().padLeft(2, "0");
  return "${n.year}${two(n.month)}${two(n.day)}_"
      "${two(n.hour)}${two(n.minute)}${two(n.second)}";
}
