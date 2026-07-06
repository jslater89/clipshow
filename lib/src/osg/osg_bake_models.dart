import "dart:convert";

import "package:flutter/foundation.dart";

import "package:obs_clipshow/src/osg/osg_models.dart";

/// Serialized [OsgBakeRecipe] schema version (independent of
/// [OsgPreset.osgPresetSchemaVersion]).
const int osgBakeRecipeSchemaVersion = 1;

/// How an [OsgBakeAnchor] resolves to a millisecond offset within a clip.
enum OsgBakeAnchorKind {
  clipStart,
  clipEnd,
  absoluteMs,
  offsetFromEndMs;

  String get label => switch (this) {
    clipStart => "Clip Start",
    clipEnd => "Clip End",
    absoluteMs => "From Start",
    offsetFromEndMs => "From End",
  };
}

/// A point in clip-relative time, resolved against the clip duration at bake time.
@immutable
class OsgBakeAnchor {
  const OsgBakeAnchor({required this.kind, this.valueMs = 0});

  const OsgBakeAnchor.clipStart() : kind = OsgBakeAnchorKind.clipStart, valueMs = 0;

  const OsgBakeAnchor.clipEnd() : kind = OsgBakeAnchorKind.clipEnd, valueMs = 0;

  const OsgBakeAnchor.absoluteMs(this.valueMs)
    : kind = OsgBakeAnchorKind.absoluteMs;

  const OsgBakeAnchor.offsetFromEndMs(this.valueMs)
    : kind = OsgBakeAnchorKind.offsetFromEndMs;

  final OsgBakeAnchorKind kind;

  /// Milliseconds; meaningful only for [OsgBakeAnchorKind.absoluteMs] and
  /// [OsgBakeAnchorKind.offsetFromEndMs].
  final int valueMs;

  Map<String, Object?> toJson() => <String, Object?>{
    "kind": kind.name,
    "valueMs": valueMs,
  };

  factory OsgBakeAnchor.fromJson(Map<String, Object?>? json) {
    if (json == null) {
      return const OsgBakeAnchor.clipStart();
    }
    final String rawKind = json["kind"] as String? ?? "clipStart";
    final OsgBakeAnchorKind kind = OsgBakeAnchorKind.values.firstWhere(
      (OsgBakeAnchorKind e) => e.name == rawKind,
      orElse: () => OsgBakeAnchorKind.clipStart,
    );
    final int valueMs = (json["valueMs"] as num?)?.round() ?? 0;
    return OsgBakeAnchor(kind: kind, valueMs: valueMs < 0 ? 0 : valueMs);
  }

  @override
  bool operator ==(Object other) {
    return other is OsgBakeAnchor &&
        other.kind == kind &&
        other.valueMs == valueMs;
  }

  @override
  int get hashCode => Object.hash(kind, valueMs);
}

/// One "show OSG slot X from [start] to [end]" instruction within a recipe.
@immutable
class OsgBakeCue {
  const OsgBakeCue({
    required this.slot,
    required this.start,
    required this.end,
  });

  final OsgPresetSlot slot;
  final OsgBakeAnchor start;
  final OsgBakeAnchor end;

  Map<String, Object?> toJson() => <String, Object?>{
    "slot": slot.name,
    "start": start.toJson(),
    "end": end.toJson(),
  };

  factory OsgBakeCue.fromJson(Map<String, Object?> json) {
    final String rawSlot = json["slot"] as String? ?? "preset1";
    final OsgPresetSlot slot = OsgPresetSlot.values.firstWhere(
      (OsgPresetSlot e) => e.name == rawSlot,
      orElse: () => OsgPresetSlot.preset1,
    );
    return OsgBakeCue(
      slot: slot,
      start: OsgBakeAnchor.fromJson(json["start"] as Map<String, Object?>?),
      end: OsgBakeAnchor.fromJson(json["end"] as Map<String, Object?>?),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is OsgBakeCue &&
        other.slot == slot &&
        other.start == start &&
        other.end == end;
  }

  @override
  int get hashCode => Object.hash(slot, start, end);
}

/// A named, workspace-level set of OSG timing cues applied during a bake export.
@immutable
class OsgBakeRecipe {
  const OsgBakeRecipe({
    required this.id,
    required this.name,
    required this.cues,
  });

  final int id;
  final String name;
  final List<OsgBakeCue> cues;

  Map<String, Object?> toJson() => <String, Object?>{
    "schemaVersion": osgBakeRecipeSchemaVersion,
    "id": id,
    "name": name,
    "cues": cues.map((OsgBakeCue c) => c.toJson()).toList(),
  };

  factory OsgBakeRecipe.fromJson(Map<String, Object?> json) {
    final List<dynamic>? rawCues = json["cues"] as List<dynamic>?;
    final List<OsgBakeCue> cues = rawCues == null
        ? <OsgBakeCue>[]
        : rawCues
              .map(
                (dynamic e) => OsgBakeCue.fromJson(
                  Map<String, Object?>.from(e as Map<dynamic, dynamic>),
                ),
              )
              .toList();
    return OsgBakeRecipe(
      id: (json["id"] as num?)?.toInt() ?? 0,
      name: json["name"] as String? ?? "",
      cues: cues,
    );
  }
}

String osgBakeAnchorLabel(OsgBakeAnchor anchor) {
  String seconds(int ms) {
    final double s = ms / 1000;
    final String txt = s == s.roundToDouble()
        ? s.toStringAsFixed(0)
        : s.toStringAsFixed(1);
    return "${txt}s";
  }

  return switch (anchor.kind) {
    OsgBakeAnchorKind.clipStart => "Clip Start",
    OsgBakeAnchorKind.clipEnd => "Clip End",
    OsgBakeAnchorKind.absoluteMs => seconds(anchor.valueMs),
    OsgBakeAnchorKind.offsetFromEndMs => "End \u2212 ${seconds(anchor.valueMs)}",
  };
}

String osgBakeCueSummaryLabel(OsgBakeCue cue) {
  return "OSG ${cue.slot.playoutHotkeyDigitLabel}: "
      "${osgBakeAnchorLabel(cue.start)} \u2192 ${osgBakeAnchorLabel(cue.end)}";
}

String encodeOsgBakeRecipesToStorageJson(List<OsgBakeRecipe> recipes) {
  return jsonEncode(recipes.map((OsgBakeRecipe r) => r.toJson()).toList());
}

List<OsgBakeRecipe> decodeOsgBakeRecipesFromStorageJson(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return const <OsgBakeRecipe>[];
  }
  try {
    final Object? decoded = jsonDecode(raw);
    if (decoded is! List<dynamic>) {
      return const <OsgBakeRecipe>[];
    }
    return decoded
        .map(
          (dynamic e) => OsgBakeRecipe.fromJson(
            Map<String, Object?>.from(e as Map<dynamic, dynamic>),
          ),
        )
        .toList();
  } catch (_) {
    return const <OsgBakeRecipe>[];
  }
}
