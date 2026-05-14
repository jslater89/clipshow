---
name: osg-preset-schema-changes
description: >-
  Checklist for changing OsgPreset serialization, schemaVersion, editor UI,
  playout, preview, and ZIP preset packs. Use when editing osg_models.dart,
  preset JSON, OSG editor, osg_playout_layer, canvas preview, or osg_preset_pack_zip.
---

# OSG Preset / Schema Changes

Work through this list before considering the change done.

## Model and persistence

- [ ] Update domain types and `copyWith` in `lib/src/osg/osg_models.dart` (and related enums/helpers).
- [ ] If JSON on disk or in exports changes: bump **`osgPresetSchemaVersion`** and handle **`schemaVersion`** in `fromJson` / migration for older versions.
- [ ] If **ZIP packs** (`osg_preset_pack_zip.dart` or callers) embed paths or fields, verify export → import round-trip with a real pack.

## UI and runtime

- [ ] **Editor** (`lib/src/features/osg/`): controls for new fields; labels Title Case per project rules.
- [ ] **Playout** (`osg_playout_layer.dart` or siblings): behavior matches editor intent for live output.
- [ ] **Canvas / preview** widgets: draft preview reflects the same motion and visibility rules as playout where applicable.

## Verification

- [ ] `dart analyze` on touched paths.
- [ ] Manual smoke: load old preset file if migration added; save and reload new preset.
