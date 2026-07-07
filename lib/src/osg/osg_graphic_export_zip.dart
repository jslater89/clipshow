import "dart:typed_data";

import "package:archive/archive.dart";

import "package:obs_clipshow/src/osg/osg_graphic_export_models.dart";
import "package:obs_clipshow/src/osg/osg_models.dart";

/// Builds a ZIP with [osgGraphicExportManifestEntry] plus one PNG per slot.
Uint8List buildOsgGraphicExportZip({
  required Map<String, Object?> manifest,
  required Map<OsgPresetSlot, Uint8List> pngBySlot,
}) {
  final Archive archive = Archive();
  archive.add(
    ArchiveFile.string(
      osgGraphicExportManifestEntry,
      encodeOsgGraphicExportManifest(manifest),
    ),
  );
  for (final MapEntry<OsgPresetSlot, Uint8List> entry in pngBySlot.entries) {
    archive.add(
      ArchiveFile.bytes(osgGraphicExportPngFileName(entry.key), entry.value),
    );
  }
  return ZipEncoder().encodeBytes(archive);
}
