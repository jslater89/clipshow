import "dart:convert";
import "dart:math" as math;
import "dart:ui";

import "package:flutter/foundation.dart";

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

/// Notional solid-template pixel size matching [frame] on [playout] (width × height).
(int, int) osgSolidTemplatePixelsForFrame(
  OsgNormRect frame,
  PlayoutOutputSize playout,
) {
  final int w = (frame.width * playout.width).round().clamp(1, 999999);
  final int h = (frame.height * playout.height).round().clamp(1, 999999);
  return (w, h);
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

/// Slide axis for OSG preset show/hide transitions (paired with fade).
enum OsgPresetVisibilityMotion {
  none,
  left,
  right,
  top,
  bottom,
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
    this.visibilityEnterMotion = OsgPresetVisibilityMotion.none,
    this.visibilityExitMotion = OsgPresetVisibilityMotion.none,
    this.visibilityEnterSlideDistanceNorm = 1.0,
    this.visibilityExitSlideDistanceNorm = 1.0,
    this.visibilityEnterDurationMs = defaultVisibilityTransitionDurationMs,
    this.visibilityExitDurationMs = defaultVisibilityTransitionDurationMs,
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

  /// How the preset enters when toggled visible (fade and optional slide).
  final OsgPresetVisibilityMotion visibilityEnterMotion;

  /// How the preset leaves when toggled off.
  final OsgPresetVisibilityMotion visibilityExitMotion;

  /// Slide distance for [visibilityEnterMotion] as a multiple of frame width or height.
  final double visibilityEnterSlideDistanceNorm;

  /// Slide distance for [visibilityExitMotion] as a multiple of frame width or height.
  final double visibilityExitSlideDistanceNorm;

  /// Fade (+ slide) duration when the preset becomes visible (milliseconds).
  final int visibilityEnterDurationMs;

  /// Fade (+ slide) duration when the preset is hidden (milliseconds).
  final int visibilityExitDurationMs;

  static const int osgPresetSchemaVersion = 10;

  /// Default for [visibilityEnterDurationMs] and [visibilityExitDurationMs].
  static const int defaultVisibilityTransitionDurationMs = 240;

  /// Fallback aspect (W÷H) for solid presets when pixel dimensions are missing.
  /// Matches [empty] frame on [PlayoutOutputSize.fallback] (1920 x 270 px).
  static const double defaultSolidTemplateAspect = 64 / 9;

  static const int defaultTemplateSolidArgb = 0xFF2D2D2D;

  static OsgPresetVisibilityMotion _visibilityMotionFromJson(Object? raw) {
    if (raw is! String) {
      return OsgPresetVisibilityMotion.none;
    }
    return OsgPresetVisibilityMotion.values.firstWhere(
      (OsgPresetVisibilityMotion e) => e.name == raw,
      orElse: () => OsgPresetVisibilityMotion.none,
    );
  }

  static double clampVisibilitySlideDistanceNorm(double v) {
    if (v < 0.05) {
      return 0.05;
    }
    if (v > 2.5) {
      return 2.5;
    }
    return v;
  }

  static double _visibilitySlideDistanceFromJson(Object? raw) {
    final double v = (raw is num ? raw.toDouble() : null) ?? 1.0;
    return clampVisibilitySlideDistanceNorm(v);
  }

  static int clampVisibilityDurationMs(int ms) {
    if (ms < 80) {
      return 80;
    }
    if (ms > 4000) {
      return 4000;
    }
    return ms;
  }

  static int _visibilityDurationFromJson(Object? raw) {
    final int v = (raw is num ? raw.round() : null) ??
        defaultVisibilityTransitionDurationMs;
    return clampVisibilityDurationMs(v);
  }

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
    const OsgNormRect frame = OsgNormRect(x: 0, y: 0.75, width: 1, height: 0.25);
    final (int solidW, int solidH) = osgSolidTemplatePixelsForFrame(
      frame,
      PlayoutOutputSize.fallback,
    );
    return OsgPreset(
      enabled: false,
      templateRelativePath: "",
      frame: frame,
      slots: <OsgSlot>[],
      templatePixelAspect: null,
      templateBackgroundKind: OsgTemplateBackgroundKind.solid,
      templateSolidArgb: defaultTemplateSolidArgb,
      layerOpacity: 1.0,
      templateCornerRadiusNorm: 0,
      templateSolidWidthPx: solidW,
      templateSolidHeightPx: solidH,
      requiredSemanticTypeIds: <int>[],
      visibilityEnterMotion: OsgPresetVisibilityMotion.none,
      visibilityExitMotion: OsgPresetVisibilityMotion.none,
      visibilityEnterSlideDistanceNorm: 1.0,
      visibilityExitSlideDistanceNorm: 1.0,
      visibilityEnterDurationMs: defaultVisibilityTransitionDurationMs,
      visibilityExitDurationMs: defaultVisibilityTransitionDurationMs,
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
    OsgPresetVisibilityMotion? visibilityEnterMotion,
    OsgPresetVisibilityMotion? visibilityExitMotion,
    double? visibilityEnterSlideDistanceNorm,
    double? visibilityExitSlideDistanceNorm,
    int? visibilityEnterDurationMs,
    int? visibilityExitDurationMs,
  }) {
    final double? nextEnterSlide = visibilityEnterSlideDistanceNorm;
    final double? nextExitSlide = visibilityExitSlideDistanceNorm;
    final int? nextEnterDur = visibilityEnterDurationMs;
    final int? nextExitDur = visibilityExitDurationMs;
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
      visibilityEnterMotion:
          visibilityEnterMotion ?? this.visibilityEnterMotion,
      visibilityExitMotion:
          visibilityExitMotion ?? this.visibilityExitMotion,
      visibilityEnterSlideDistanceNorm: nextEnterSlide != null
          ? OsgPreset.clampVisibilitySlideDistanceNorm(nextEnterSlide)
          : this.visibilityEnterSlideDistanceNorm,
      visibilityExitSlideDistanceNorm: nextExitSlide != null
          ? OsgPreset.clampVisibilitySlideDistanceNorm(nextExitSlide)
          : this.visibilityExitSlideDistanceNorm,
      visibilityEnterDurationMs: nextEnterDur != null
          ? OsgPreset.clampVisibilityDurationMs(nextEnterDur)
          : this.visibilityEnterDurationMs,
      visibilityExitDurationMs: nextExitDur != null
          ? OsgPreset.clampVisibilityDurationMs(nextExitDur)
          : this.visibilityExitDurationMs,
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
    "visibilityEnterMotion": visibilityEnterMotion.name,
    "visibilityExitMotion": visibilityExitMotion.name,
    "visibilityEnterSlideDistanceNorm":
        OsgPreset.clampVisibilitySlideDistanceNorm(
          visibilityEnterSlideDistanceNorm,
        ),
    "visibilityExitSlideDistanceNorm":
        OsgPreset.clampVisibilitySlideDistanceNorm(
          visibilityExitSlideDistanceNorm,
        ),
    "visibilityEnterDurationMs":
        OsgPreset.clampVisibilityDurationMs(visibilityEnterDurationMs),
    "visibilityExitDurationMs":
        OsgPreset.clampVisibilityDurationMs(visibilityExitDurationMs),
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
    final OsgNormRect frame = OsgNormRect.fromJson(
      json["frame"] as Map<String, Object?>?,
    );
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
        final (int fw, int fh) = osgSolidTemplatePixelsForFrame(
          frame,
          PlayoutOutputSize.fallback,
        );
        solidW = fw;
        solidH = fh;
      }
    }
    OsgPreset preset = OsgPreset(
      enabled: json["enabled"] == true,
      templateRelativePath: path,
      frame: frame,
      slots: slots,
      templatePixelAspect: templatePixelAspect,
      templateBackgroundKind: kind,
      templateSolidArgb: solidArgb,
      layerOpacity: layerOp.clamp(0.0, 1.0),
      templateCornerRadiusNorm: cornerNorm,
      templateSolidWidthPx: solidW,
      templateSolidHeightPx: solidH,
      requiredSemanticTypeIds: requiredSemanticTypeIds,
      visibilityEnterMotion: _visibilityMotionFromJson(
        json["visibilityEnterMotion"],
      ),
      visibilityExitMotion: _visibilityMotionFromJson(
        json["visibilityExitMotion"],
      ),
      visibilityEnterSlideDistanceNorm: _visibilitySlideDistanceFromJson(
        json["visibilityEnterSlideDistanceNorm"],
      ),
      visibilityExitSlideDistanceNorm: _visibilitySlideDistanceFromJson(
        json["visibilityExitSlideDistanceNorm"],
      ),
      visibilityEnterDurationMs: _visibilityDurationFromJson(
        json["visibilityEnterDurationMs"],
      ),
      visibilityExitDurationMs: _visibilityDurationFromJson(
        json["visibilityExitDurationMs"],
      ),
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
      visibilityEnterMotion: visibilityEnterMotion,
      visibilityExitMotion: visibilityExitMotion,
      visibilityEnterSlideDistanceNorm: visibilityEnterSlideDistanceNorm,
      visibilityExitSlideDistanceNorm: visibilityExitSlideDistanceNorm,
      visibilityEnterDurationMs: visibilityEnterDurationMs,
      visibilityExitDurationMs: visibilityExitDurationMs,
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

/// Playout / preview hotkey order: 6, 7, 8, 9, 0 (indices 0–4).
enum OsgPresetSlot {
  preset1,
  preset2,
  preset3,
  preset4,
  preset5,
}

extension OsgPresetSlotPlayoutHotkey on OsgPresetSlot {
  /// Digit label on the keyboard row (matches [OsgPresetSlot] order).
  String get playoutHotkeyDigitLabel => switch (this) {
    OsgPresetSlot.preset1 => "6",
    OsgPresetSlot.preset2 => "7",
    OsgPresetSlot.preset3 => "8",
    OsgPresetSlot.preset4 => "9",
    OsgPresetSlot.preset5 => "0",
  };

  /// Index into [OsgWorkspaceConfig.workspacePresets] (0..4).
  int get presetIndex => index;
}

/// Which OSG overlays are toggled on in preview / playout (hotkeys 6–0).
@immutable
class OsgPresetVisibility {
  const OsgPresetVisibility({
    required this.preset1,
    required this.preset2,
    required this.preset3,
    required this.preset4,
    required this.preset5,
  });

  const OsgPresetVisibility.allOff()
    : preset1 = false,
      preset2 = false,
      preset3 = false,
      preset4 = false,
      preset5 = false;

  final bool preset1;
  final bool preset2;
  final bool preset3;
  final bool preset4;
  final bool preset5;

  /// Builds visibility from a list (e.g. legacy length-3); missing entries are false.
  factory OsgPresetVisibility.fromBoolList(List<bool> values) {
    bool g(int i) => i < values.length ? values[i] : false;
    return OsgPresetVisibility(
      preset1: g(0),
      preset2: g(1),
      preset3: g(2),
      preset4: g(3),
      preset5: g(4),
    );
  }

  bool operator [](OsgPresetSlot slot) => switch (slot) {
    OsgPresetSlot.preset1 => preset1,
    OsgPresetSlot.preset2 => preset2,
    OsgPresetSlot.preset3 => preset3,
    OsgPresetSlot.preset4 => preset4,
    OsgPresetSlot.preset5 => preset5,
  };

  OsgPresetVisibility withSlot(OsgPresetSlot slot, bool value) => switch (slot) {
    OsgPresetSlot.preset1 => OsgPresetVisibility(
      preset1: value,
      preset2: preset2,
      preset3: preset3,
      preset4: preset4,
      preset5: preset5,
    ),
    OsgPresetSlot.preset2 => OsgPresetVisibility(
      preset1: preset1,
      preset2: value,
      preset3: preset3,
      preset4: preset4,
      preset5: preset5,
    ),
    OsgPresetSlot.preset3 => OsgPresetVisibility(
      preset1: preset1,
      preset2: preset2,
      preset3: value,
      preset4: preset4,
      preset5: preset5,
    ),
    OsgPresetSlot.preset4 => OsgPresetVisibility(
      preset1: preset1,
      preset2: preset2,
      preset3: preset3,
      preset4: value,
      preset5: preset5,
    ),
    OsgPresetSlot.preset5 => OsgPresetVisibility(
      preset1: preset1,
      preset2: preset2,
      preset3: preset3,
      preset4: preset4,
      preset5: value,
    ),
  };

  @override
  bool operator ==(Object other) {
    return other is OsgPresetVisibility &&
        other.preset1 == preset1 &&
        other.preset2 == preset2 &&
        other.preset3 == preset3 &&
        other.preset4 == preset4 &&
        other.preset5 == preset5;
  }

  @override
  int get hashCode => Object.hash(
    preset1,
    preset2,
    preset3,
    preset4,
    preset5,
  );
}

class OsgWorkspaceConfig {
  const OsgWorkspaceConfig({required this.presets});

  static OsgWorkspaceConfig fallback() {
    return OsgWorkspaceConfig(
      presets: <OsgPreset>[
        OsgPreset.empty(),
        OsgPreset.empty(),
        OsgPreset.empty(),
        OsgPreset.empty(),
        OsgPreset.empty(),
      ],
    );
  }

  final List<OsgPreset> presets;

  /// Five presets aligned with playout hotkeys 6, 7, 8, 9, and 0.
  List<OsgPreset> get workspacePresets {
    final List<OsgPreset> p = List<OsgPreset>.from(presets);
    while (p.length < 5) {
      p.add(OsgPreset.empty());
    }
    if (p.length > 5) {
      return p.sublist(0, 5);
    }
    return p;
  }

  String encodeToStorageJson() {
    final List<OsgPreset> p = workspacePresets;
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
    for (final OsgPreset preset in workspacePresets) {
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
