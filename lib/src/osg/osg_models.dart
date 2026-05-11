import "dart:convert";
import "dart:math" as math;
import "dart:ui";

/// Logical playout / broadcast canvas size (pixels). Used for window sizing and OSG 0..1 space.
class PlayoutOutputSize {
  const PlayoutOutputSize({required this.width, required this.height});

  static const PlayoutOutputSize fallback = PlayoutOutputSize(
    width: 1920,
    height: 1080,
  );

  final int width;
  final int height;

  Size get size => Size(width.toDouble(), height.toDouble());

  double get aspectRatio => width / height;

  bool get isValid => width > 0 && height > 0;
}

/// Normalized rectangle in 0..1 relative to [PlayoutOutputSize].
class OsgNormRect {
  const OsgNormRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  static const OsgNormRect unit = OsgNormRect(x: 0, y: 0, width: 1, height: 1);

  final double x;
  final double y;
  final double width;
  final double height;

  Map<String, Object?> toJson() => <String, Object?>{
    "x": x,
    "y": y,
    "width": width,
    "height": height,
  };

  @override
  bool operator ==(Object other) {
    return other is OsgNormRect &&
        other.x == x &&
        other.y == y &&
        other.width == width &&
        other.height == height;
  }

  @override
  int get hashCode => Object.hash(x, y, width, height);

  factory OsgNormRect.fromJson(Map<String, Object?>? json) {
    if (json == null) {
      return unit;
    }
    double d(String key, double def) {
      final Object? v = json[key];
      if (v is num) {
        return v.toDouble();
      }
      return def;
    }

    return OsgNormRect(
      x: d("x", 0),
      y: d("y", 0),
      width: d("width", 1),
      height: d("height", 1),
    );
  }
}

enum OsgTextSource {
  fixed,
  semantic,
  annotation;

  String get label => switch (this) {
    fixed => "Text",
    semantic => "Tag value",
    annotation => "Annotation",
  };
}

/// Horizontal alignment of text inside a slot box.
enum OsgSlotTextAlign {
  left,
  center,
  right,
}

/// Vertical alignment of text inside a slot box.
enum OsgSlotVerticalAlign {
  top,
  center,
  bottom,
}

/// Whether the preset graphic behind text is a template image or a solid fill.
enum OsgTemplateBackgroundKind {
  image,
  solid,
}

class OsgSlot {
  const OsgSlot({
    required this.textSource,
    this.fixedText = "",
    this.semanticTypeId,
    this.fontSizeNorm = 0.04,
    this.fontFamily,
    this.box = OsgNormRect.unit,
    this.textColorArgb = 0xFFFFFFFF,
    this.textAlign = OsgSlotTextAlign.left,
    this.verticalAlign = OsgSlotVerticalAlign.center,
  });

  final OsgTextSource textSource;
  final String fixedText;
  final int? semanticTypeId;

  /// Font size as a fraction of the **template frame** height (0..1 graphic space).
  final double fontSizeNorm;

  /// Registered font family name, or null for the platform default.
  final String? fontFamily;

  /// 0..1 rectangle **inside the template frame** (same space as the graphic image).
  final OsgNormRect box;

  /// ARGB for this slot’s text (including alpha).
  final int textColorArgb;

  final OsgSlotTextAlign textAlign;

  final OsgSlotVerticalAlign verticalAlign;

  Map<String, Object?> toJson() => <String, Object?>{
    "textSource": textSource.name,
    "fixedText": fixedText,
    "semanticTypeId": semanticTypeId,
    "fontSizeNorm": fontSizeNorm,
    "fontFamily": fontFamily,
    "box": box.toJson(),
    "textColorArgb": textColorArgb,
    "textAlign": textAlign.name,
    "verticalAlign": verticalAlign.name,
  };

  static int _textColorFromJson(
    Map<String, Object?> json, {
    required int presetSlotTextFallback,
  }) {
    if (json.containsKey("textColorArgb")) {
      return (json["textColorArgb"] as num?)?.toInt() ?? 0xFFFFFFFF;
    }
    return presetSlotTextFallback;
  }

  factory OsgSlot.fromJson(
    Map<String, Object?> json, {
    int presetSlotTextFallback = 0xFFFFFFFF,
  }) {
    final String raw = json["textSource"] as String? ?? "fixed";
    final OsgTextSource source = OsgTextSource.values.firstWhere(
      (OsgTextSource e) => e.name == raw,
      orElse: () => OsgTextSource.fixed,
    );
    final Object? st = json["semanticTypeId"];
    final String? ff = json["fontFamily"] as String?;
    final String rawAlign = json["textAlign"] as String? ?? "left";
    final OsgSlotTextAlign align = OsgSlotTextAlign.values.firstWhere(
      (OsgSlotTextAlign e) => e.name == rawAlign,
      orElse: () => OsgSlotTextAlign.left,
    );
    final String rawVAlign = json["verticalAlign"] as String? ?? "center";
    final OsgSlotVerticalAlign vAlign = OsgSlotVerticalAlign.values.firstWhere(
      (OsgSlotVerticalAlign e) => e.name == rawVAlign,
      orElse: () => OsgSlotVerticalAlign.center,
    );
    return OsgSlot(
      textSource: source,
      fixedText: json["fixedText"] as String? ?? "",
      semanticTypeId: st is int ? st : int.tryParse("$st"),
      fontSizeNorm: (json["fontSizeNorm"] as num?)?.toDouble() ?? 0.04,
      fontFamily: ff != null && ff.trim().isEmpty ? null : ff?.trim(),
      box: OsgNormRect.fromJson(json["box"] as Map<String, Object?>?),
      textColorArgb: _textColorFromJson(
        json,
        presetSlotTextFallback: presetSlotTextFallback,
      ),
      textAlign: align,
      verticalAlign: vAlign,
    );
  }

  static const Object _omitFontFamily = Object();

  OsgSlot copyWith({
    OsgTextSource? textSource,
    String? fixedText,
    int? semanticTypeId,
    double? fontSizeNorm,
    Object? fontFamily = _omitFontFamily,
    OsgNormRect? box,
    int? textColorArgb,
    OsgSlotTextAlign? textAlign,
    OsgSlotVerticalAlign? verticalAlign,
  }) {
    return OsgSlot(
      textSource: textSource ?? this.textSource,
      fixedText: fixedText ?? this.fixedText,
      semanticTypeId: semanticTypeId ?? this.semanticTypeId,
      fontSizeNorm: fontSizeNorm ?? this.fontSizeNorm,
      fontFamily: identical(fontFamily, _omitFontFamily)
          ? this.fontFamily
          : fontFamily as String?,
      box: box ?? this.box,
      textColorArgb: textColorArgb ?? this.textColorArgb,
      textAlign: textAlign ?? this.textAlign,
      verticalAlign: verticalAlign ?? this.verticalAlign,
    );
  }
}

class OsgPreset {
  const OsgPreset({
    required this.enabled,
    required this.templateRelativePath,
    required this.frame,
    required this.slots,
    this.templatePixelAspect,
    this.templateBackgroundKind = OsgTemplateBackgroundKind.solid,
    this.templateSolidArgb = 0xFF2D2D2D,
    this.layerOpacity = 1.0,
    this.templateCornerRadiusNorm = 0,
    this.templateSolidWidthPx = 0,
    this.templateSolidHeightPx = 0,
    this.requiredSemanticTypeIds = const <int>[],
  });

  /// Width ÷ height of the template image in pixels; used to lock [frame] aspect on screen.
  /// For [OsgTemplateBackgroundKind.solid], [templateSolidWidthPx] / [templateSolidHeightPx] when both are positive.
  final double? templatePixelAspect;

  /// When [solid], [templateRelativePath] is ignored for rendering.
  final OsgTemplateBackgroundKind templateBackgroundKind;

  /// ARGB fill for the template area when [templateBackgroundKind] is [solid].
  final int templateSolidArgb;

  /// Notional pixel width of the solid template graphic (with [templateSolidHeightPx] sets aspect). 0 when unused (image presets).
  final int templateSolidWidthPx;

  /// Notional pixel height of the solid template graphic.
  final int templateSolidHeightPx;

  /// Multiplies the whole preset layer (0..1); combined with playout visibility toggles.
  final double layerOpacity;

  /// Rounded corners on the template frame: radius = this × min(frame width, frame height) in px (clamped to half the shorter side). 0 = square.
  final double templateCornerRadiusNorm;

  final bool enabled;
  final String templateRelativePath;
  final OsgNormRect frame;
  final List<OsgSlot> slots;

  /// Semantic tag type ids that must appear on the media row for this overlay
  /// to be allowed (each id must match at least one tag attachment).
  final List<int> requiredSemanticTypeIds;

  static const int osgPresetSchemaVersion = 8;

  /// Logical template size used when [templatePixelAspect] is null and background is solid.
  static const double defaultSolidTemplateAspect = 400 / 200;

  static const int defaultTemplateSolidArgb = 0xFF2D2D2D;

  static OsgTemplateBackgroundKind _kindFromJson(
    Object? raw,
    String path,
  ) {
    if (raw == "solid") {
      return OsgTemplateBackgroundKind.solid;
    }
    if (raw == "image") {
      return OsgTemplateBackgroundKind.image;
    }
    return path.trim().isNotEmpty
        ? OsgTemplateBackgroundKind.image
        : OsgTemplateBackgroundKind.solid;
  }

  static OsgPreset empty() {
    return const OsgPreset(
      enabled: false,
      templateRelativePath: "",
      frame: OsgNormRect(x: 0, y: 0.75, width: 1, height: 0.25),
      slots: <OsgSlot>[],
      templatePixelAspect: null,
      templateBackgroundKind: OsgTemplateBackgroundKind.solid,
      templateSolidArgb: defaultTemplateSolidArgb,
      layerOpacity: 1.0,
      templateCornerRadiusNorm: 0,
      templateSolidWidthPx: 400,
      templateSolidHeightPx: 200,
      requiredSemanticTypeIds: <int>[],
    );
  }

  bool semanticRequirementsSatisfiedBy(Set<int> semanticTypeIdsOnMedia) {
    for (final int id in requiredSemanticTypeIds) {
      if (!semanticTypeIdsOnMedia.contains(id)) {
        return false;
      }
    }
    return true;
  }

  List<int> missingSemanticRequirements(Set<int> semanticTypeIdsOnMedia) {
    final List<int> out = <int>[];
    for (final int id in requiredSemanticTypeIds) {
      if (!semanticTypeIdsOnMedia.contains(id)) {
        out.add(id);
      }
    }
    return out;
  }

  /// Corner radius in pixels for the rendered frame of size [frameWidthPx]×[frameHeightPx].
  double templateCornerRadiusPx(double frameWidthPx, double frameHeightPx) {
    final double n = templateCornerRadiusNorm;
    if (n <= 0) {
      return 0;
    }
    final double m = math.min(frameWidthPx, frameHeightPx);
    return (m * n).clamp(0.0, m * 0.5);
  }

  /// Aspect ratio (width ÷ height) for frame locking and previews.
  double get templateAspectRatioForFrame {
    if (templateBackgroundKind == OsgTemplateBackgroundKind.image) {
      if (templatePixelAspect != null && templatePixelAspect! > 1e-9) {
        return templatePixelAspect!;
      }
      return 16 / 9;
    }
    if (templateSolidWidthPx > 0 && templateSolidHeightPx > 0) {
      return templateSolidWidthPx / templateSolidHeightPx;
    }
    if (templatePixelAspect != null && templatePixelAspect! > 1e-9) {
      return templatePixelAspect!;
    }
    return defaultSolidTemplateAspect;
  }

  OsgPreset copyWith({
    bool? enabled,
    String? templateRelativePath,
    OsgNormRect? frame,
    List<OsgSlot>? slots,
    double? templatePixelAspect,
    OsgTemplateBackgroundKind? templateBackgroundKind,
    int? templateSolidArgb,
    double? layerOpacity,
    double? templateCornerRadiusNorm,
    int? templateSolidWidthPx,
    int? templateSolidHeightPx,
    List<int>? requiredSemanticTypeIds,
  }) {
    return OsgPreset(
      enabled: enabled ?? this.enabled,
      templateRelativePath: templateRelativePath ?? this.templateRelativePath,
      frame: frame ?? this.frame,
      slots: slots ?? this.slots,
      templatePixelAspect: templatePixelAspect ?? this.templatePixelAspect,
      templateBackgroundKind:
          templateBackgroundKind ?? this.templateBackgroundKind,
      templateSolidArgb: templateSolidArgb ?? this.templateSolidArgb,
      layerOpacity: layerOpacity ?? this.layerOpacity,
      templateCornerRadiusNorm:
          templateCornerRadiusNorm ?? this.templateCornerRadiusNorm,
      templateSolidWidthPx:
          templateSolidWidthPx ?? this.templateSolidWidthPx,
      templateSolidHeightPx:
          templateSolidHeightPx ?? this.templateSolidHeightPx,
      requiredSemanticTypeIds:
          requiredSemanticTypeIds ?? this.requiredSemanticTypeIds,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    "schemaVersion": osgPresetSchemaVersion,
    "enabled": enabled,
    "templateRelativePath": templateRelativePath,
    "templatePixelAspect": templatePixelAspect,
    "templateBackgroundKind": templateBackgroundKind.name,
    "templateSolidArgb": templateSolidArgb,
    "layerOpacity": layerOpacity,
    "templateCornerRadiusNorm": templateCornerRadiusNorm,
    "templateSolidWidthPx": templateSolidWidthPx,
    "templateSolidHeightPx": templateSolidHeightPx,
    "frame": frame.toJson(),
    "slots": slots.map((OsgSlot s) => s.toJson()).toList(),
    "requiredSemanticTypeIds": requiredSemanticTypeIds,
  };

  factory OsgPreset.fromJson(Map<String, Object?> json) {
    final int presetSlotTextFallback =
        (json["slotTextArgb"] as num?)?.toInt() ?? 0xFFFFFFFF;
    final List<dynamic>? rawSlots = json["slots"] as List<dynamic>?;
    final List<OsgSlot> slots = rawSlots == null
        ? <OsgSlot>[]
        : rawSlots
              .map(
                (dynamic e) => OsgSlot.fromJson(
                  Map<String, Object?>.from(e as Map<dynamic, dynamic>),
                  presetSlotTextFallback: presetSlotTextFallback,
                ),
              )
              .toList();
    final List<int> requiredSemanticTypeIds =
        _requiredSemanticTypeIdsFromJson(json);
    final int ver = (json["schemaVersion"] as num?)?.toInt() ?? 1;
    final Object? tpa = json["templatePixelAspect"];
    final double? templatePixelAspect = tpa is num ? tpa.toDouble() : null;
    final String path = json["templateRelativePath"] as String? ?? "";
    final OsgTemplateBackgroundKind kind = _kindFromJson(
      json["templateBackgroundKind"],
      path,
    );
    final int solidArgb =
        (json["templateSolidArgb"] as num?)?.toInt() ?? defaultTemplateSolidArgb;
    final double layerOp =
        (json["layerOpacity"] as num?)?.toDouble() ?? 1.0;
    final double cornerNorm =
        ((json["templateCornerRadiusNorm"] as num?)?.toDouble() ?? 0)
            .clamp(0.0, 0.5);
    int solidW = (json["templateSolidWidthPx"] as num?)?.toInt() ?? 0;
    int solidH = (json["templateSolidHeightPx"] as num?)?.toInt() ?? 0;
    if (kind == OsgTemplateBackgroundKind.solid &&
        (solidW <= 0 || solidH <= 0)) {
      final double? a = templatePixelAspect;
      if (a != null && a > 1e-9) {
        solidH = 1000;
        solidW = (a * solidH).round().clamp(1, 999999);
      } else {
        solidW = 400;
        solidH = 200;
      }
    }
    OsgPreset preset = OsgPreset(
      enabled: json["enabled"] == true,
      templateRelativePath: path,
      frame: OsgNormRect.fromJson(json["frame"] as Map<String, Object?>?),
      slots: slots,
      templatePixelAspect: templatePixelAspect,
      templateBackgroundKind: kind,
      templateSolidArgb: solidArgb,
      layerOpacity: layerOp.clamp(0.0, 1.0),
      templateCornerRadiusNorm: cornerNorm,
      templateSolidWidthPx: solidW,
      templateSolidHeightPx: solidH,
      requiredSemanticTypeIds: requiredSemanticTypeIds,
    );
    if (ver < 2) {
      preset = preset._migrateSlotsToGraphicLocal();
    }
    return preset;
  }

  OsgPreset _migrateSlotsToGraphicLocal() {
    final OsgNormRect fr = frame;
    final double fw = fr.width <= 1e-9 ? 1.0 : fr.width;
    final double fh = fr.height <= 1e-9 ? 1.0 : fr.height;
    final List<OsgSlot> migrated = slots.map((OsgSlot s) {
      final OsgNormRect b = s.box;
      return OsgSlot(
        textSource: s.textSource,
        fixedText: s.fixedText,
        semanticTypeId: s.semanticTypeId,
        fontSizeNorm: s.fontSizeNorm,
        fontFamily: s.fontFamily,
        textColorArgb: s.textColorArgb,
        textAlign: s.textAlign,
        verticalAlign: s.verticalAlign,
        box: OsgNormRect(
          x: ((b.x - fr.x) / fw).clamp(0.0, 1.0),
          y: ((b.y - fr.y) / fh).clamp(0.0, 1.0),
          width: (b.width / fw).clamp(0.02, 1.0),
          height: (b.height / fh).clamp(0.02, 1.0),
        ),
      );
    }).toList();
    return OsgPreset(
      enabled: enabled,
      templateRelativePath: templateRelativePath,
      frame: fr,
      slots: migrated,
      templatePixelAspect: templatePixelAspect,
      templateBackgroundKind: templateBackgroundKind,
      templateSolidArgb: templateSolidArgb,
      layerOpacity: layerOpacity,
      templateCornerRadiusNorm: templateCornerRadiusNorm,
      templateSolidWidthPx: templateSolidWidthPx,
      templateSolidHeightPx: templateSolidHeightPx,
      requiredSemanticTypeIds: requiredSemanticTypeIds,
    );
  }

  static List<int> _requiredSemanticTypeIdsFromJson(
    Map<String, Object?> json,
  ) {
    final Object? raw = json["requiredSemanticTypeIds"];
    if (raw is! List<dynamic>) {
      return const <int>[];
    }
    final Set<int> seen = <int>{};
    final List<int> out = <int>[];
    for (final Object? e in raw) {
      final int? id = e is int ? e : int.tryParse("$e");
      if (id != null && seen.add(id)) {
        out.add(id);
      }
    }
    out.sort();
    return out;
  }
}

class OsgWorkspaceConfig {
  const OsgWorkspaceConfig({required this.presets});

  static OsgWorkspaceConfig fallback() {
    return OsgWorkspaceConfig(
      presets: <OsgPreset>[
        OsgPreset.empty(),
        OsgPreset.empty(),
        OsgPreset.empty(),
      ],
    );
  }

  final List<OsgPreset> presets;

  List<OsgPreset> get threePresets {
    final List<OsgPreset> p = List<OsgPreset>.from(presets);
    while (p.length < 3) {
      p.add(OsgPreset.empty());
    }
    return p.sublist(0, 3);
  }

  String encodeToStorageJson() {
    final List<OsgPreset> p = threePresets;
    return jsonEncode(p.map((OsgPreset e) => e.toJson()).toList());
  }

  static OsgWorkspaceConfig decodeFromStorageJson(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return fallback();
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List<dynamic>) {
        return fallback();
      }
      final List<OsgPreset> list = decoded
          .map(
            (dynamic e) => OsgPreset.fromJson(
              Map<String, Object?>.from(e as Map<dynamic, dynamic>),
            ),
          )
          .toList();
      return OsgWorkspaceConfig(presets: list);
    } catch (_) {
      return fallback();
    }
  }

  /// Returns distinct semantic type ids referenced by enabled presets.
  Set<int> referencedSemanticTypeIds() {
    final Set<int> ids = <int>{};
    for (final OsgPreset preset in threePresets) {
      if (!preset.enabled) {
        continue;
      }
      ids.addAll(preset.requiredSemanticTypeIds);
      for (final OsgSlot slot in preset.slots) {
        if (slot.textSource == OsgTextSource.semantic &&
            slot.semanticTypeId != null) {
          ids.add(slot.semanticTypeId!);
        }
      }
    }
    return ids;
  }
}

class TagSemanticType {
  const TagSemanticType({
    required this.id,
    required this.name,
    this.iconCodePoint,
  });

  final int id;
  final String name;
  final int? iconCodePoint;
}

String osgMissingSemanticRequirementsMessage({
  required OsgPreset preset,
  required Set<int> semanticTypeIdsOnMedia,
  required List<TagSemanticType> tagSemanticTypes,
}) {
  final List<int> missing =
      preset.missingSemanticRequirements(semanticTypeIdsOnMedia);
  if (missing.isEmpty) {
    return "";
  }
  final Map<int, String> names = <int, String>{
    for (final TagSemanticType t in tagSemanticTypes) t.id: t.name,
  };
  final String joined = missing
      .map((int id) => names[id] ?? "Type $id")
      .join(", ");
  return "This Overlay Needs Semantic Tag Type(s): $joined.";
}

/// Tag text with optional semantic type for saved-tag shelf, capture queue, and bulk apply.
class ShelfTagEntry {
  const ShelfTagEntry({required this.name, this.semanticTypeId});

  final String name;
  final int? semanticTypeId;

  @override
  bool operator ==(Object other) {
    return other is ShelfTagEntry &&
        other.name == name &&
        other.semanticTypeId == semanticTypeId;
  }

  @override
  int get hashCode => Object.hash(name, semanticTypeId);
}

class MediaTagAttachment {
  const MediaTagAttachment({
    required this.mediaTagId,
    required this.tagId,
    required this.tagName,
    this.semanticTypeId,
    this.semanticTypeName,
    this.semanticTypeIconCodePoint,
  });

  final int mediaTagId;
  final int tagId;
  final String tagName;
  final int? semanticTypeId;
  final String? semanticTypeName;
  final int? semanticTypeIconCodePoint;
}
