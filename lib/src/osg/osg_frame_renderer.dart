import "dart:io";
import "dart:math" as math;
import "dart:typed_data";
import "dart:ui" as ui;

import "package:flutter/painting.dart";
import "package:path/path.dart" as p;

import "package:obs_clipshow/src/osg/osg_bake_cue_resolver.dart";
import "package:obs_clipshow/src/osg/osg_bake_models.dart";
import "package:obs_clipshow/src/osg/osg_models.dart";

/// Offline OSG frame renderer for bake export.
///
/// Draws the same composition as playout's `OsgPlayoutLayer` (template image
/// or solid fill, rounded-corner clip, per-slot text) directly with
/// [ui.Canvas] / [TextPainter] — no widget tree, no [ui.FlutterView] — at a
/// fixed output canvas size ([PlayoutOutputSize]).
///
/// Must run on the root isolate (`dart:ui` restriction). Template images are
/// decoded once in [loadAssets], then [renderFramePng] is called per frame.
///
/// Known simplification vs playout: text shrink-to-fit approximates the live
/// `FittedBox.scaleDown` with a uniform scale when the laid-out text overflows
/// its slot box; the `fontPx` clamp formula itself matches playout exactly.
class OsgFrameRenderer {
  OsgFrameRenderer({
    required this.presets,
    required this.cues,
    required this.clipDurationMs,
    required this.outputWidthPx,
    required this.outputHeightPx,
    required this.semanticTextByTypeId,
    required this.annotationsText,
    required this.workspaceRoot,
  });

  /// Five presets in [OsgPresetSlot] order (z-order matches `OsgPlayoutLayer`).
  final List<OsgPreset> presets;
  final List<OsgBakeCue> cues;
  final int clipDurationMs;
  final int outputWidthPx;
  final int outputHeightPx;
  final Map<int, String> semanticTextByTypeId;
  final String annotationsText;
  final String workspaceRoot;

  final Map<int, ui.Image> _templateImageByPresetIndex = <int, ui.Image>{};
  bool _assetsLoaded = false;

  /// Distinct slots referenced by [cues] (only these presets are drawn).
  Set<OsgPresetSlot> get _cuedSlots =>
      cues.map((OsgBakeCue c) => c.slot).toSet();

  String? _templateAbsolutePath(OsgPreset preset) {
    final String root = workspaceRoot.trim();
    final String rel = preset.templateRelativePath.trim();
    if (root.isEmpty || rel.isEmpty) {
      return null;
    }
    final String abs = p.normalize(
      p.join(p.absolute(root), rel.replaceAll("/", p.separator)),
    );
    if (!p.isAbsolute(abs)) {
      return null;
    }
    return abs;
  }

  /// Decodes template images for cued, enabled, image-backed presets.
  /// Presets whose template cannot be loaded are skipped at render time
  /// (mirrors playout's `canRenderImage` guard).
  Future<void> loadAssets() async {
    for (final OsgPresetSlot slot in _cuedSlots) {
      final int index = slot.presetIndex;
      if (index < 0 || index >= presets.length) {
        continue;
      }
      final OsgPreset preset = presets[index];
      if (!preset.enabled ||
          preset.templateBackgroundKind != OsgTemplateBackgroundKind.image) {
        continue;
      }
      final String? abs = _templateAbsolutePath(preset);
      if (abs == null) {
        continue;
      }
      final File file = File(abs);
      if (!await file.exists()) {
        continue;
      }
      try {
        final Uint8List bytes = await file.readAsBytes();
        final ui.Codec codec = await ui.instantiateImageCodec(bytes);
        final ui.FrameInfo frame = await codec.getNextFrame();
        _templateImageByPresetIndex[index] = frame.image;
        codec.dispose();
      } catch (_) {
        // Unreadable/corrupt template: preset renders nothing, like playout.
      }
    }
    _assetsLoaded = true;
  }

  void dispose() {
    for (final ui.Image image in _templateImageByPresetIndex.values) {
      image.dispose();
    }
    _templateImageByPresetIndex.clear();
  }

  /// Renders the full OSG overlay at [tMs] as a transparent PNG of
  /// [outputWidthPx] x [outputHeightPx].
  Future<Uint8List> renderFramePng(int tMs) async {
    assert(_assetsLoaded, "Call loadAssets() before renderFramePng().");
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(recorder);
    final double w = outputWidthPx.toDouble();
    final double h = outputHeightPx.toDouble();

    for (final OsgPresetSlot slot in OsgPresetSlot.values) {
      final int index = slot.presetIndex;
      if (index < 0 || index >= presets.length) {
        continue;
      }
      _drawPreset(canvas, slot, presets[index], tMs, w, h);
    }

    final ui.Picture picture = recorder.endRecording();
    final ui.Image image = await picture.toImage(outputWidthPx, outputHeightPx);
    picture.dispose();
    try {
      final ByteData? bytes = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (bytes == null) {
        throw StateError("PNG encode returned null byte data.");
      }
      return bytes.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  void _drawPreset(
    ui.Canvas canvas,
    OsgPresetSlot slot,
    OsgPreset preset,
    int tMs,
    double w,
    double h,
  ) {
    if (!preset.enabled) {
      return;
    }
    final bool useSolid =
        preset.templateBackgroundKind == OsgTemplateBackgroundKind.solid;
    final ui.Image? templateImage =
        _templateImageByPresetIndex[slot.presetIndex];
    if (!useSolid && templateImage == null) {
      return;
    }

    final OsgNormRect fr = preset.frame;
    final double left = fr.x * w;
    final double top = fr.y * h;
    final double fw = fr.width * w;
    final double fh = fr.height * h;
    if (fw <= 0 || fh <= 0) {
      return;
    }

    final ({double opacity, Offset offset}) vis = sampleSlotVisibilityAt(
      slot: slot,
      preset: preset,
      cues: cues,
      tMs: tMs,
      clipDurationMs: clipDurationMs,
      frameWidthPx: fw,
      frameHeightPx: fh,
    );
    final double opacity = vis.opacity.clamp(0.0, 1.0);
    if (opacity <= 0) {
      return;
    }

    canvas.save();
    canvas.translate(left + vis.offset.dx, top + vis.offset.dy);
    final bool needsLayer = opacity < 1.0;
    if (needsLayer) {
      canvas.saveLayer(
        null,
        ui.Paint()..color = const ui.Color(0xFFFFFFFF).withValues(alpha: opacity),
      );
    }

    final double cornerR = preset.templateCornerRadiusPx(fw, fh);
    if (cornerR > 0) {
      canvas.clipRRect(
        ui.RRect.fromRectAndRadius(
          ui.Rect.fromLTWH(0, 0, fw, fh),
          ui.Radius.circular(cornerR),
        ),
      );
    }

    final ui.Rect frameRect = ui.Rect.fromLTWH(0, 0, fw, fh);
    if (useSolid) {
      canvas.drawRect(
        frameRect,
        ui.Paint()..color = ui.Color(preset.templateSolidArgb),
      );
    } else {
      _drawImageCover(canvas, templateImage!, frameRect);
    }

    for (final OsgSlot textSlot in preset.slots) {
      _drawSlotText(canvas, textSlot, fw, fh);
    }

    if (needsLayer) {
      canvas.restore();
    }
    canvas.restore();
  }

  /// Matches `Image.file(fit: BoxFit.cover, alignment: Alignment.center)`.
  void _drawImageCover(ui.Canvas canvas, ui.Image image, ui.Rect dst) {
    final double iw = image.width.toDouble();
    final double ih = image.height.toDouble();
    if (iw <= 0 || ih <= 0) {
      return;
    }
    final double srcAspect = iw / ih;
    final double dstAspect = dst.width / dst.height;
    ui.Rect src;
    if (srcAspect > dstAspect) {
      final double srcW = ih * dstAspect;
      src = ui.Rect.fromLTWH((iw - srcW) / 2, 0, srcW, ih);
    } else {
      final double srcH = iw / dstAspect;
      src = ui.Rect.fromLTWH(0, (ih - srcH) / 2, iw, srcH);
    }
    canvas.drawImageRect(
      image,
      src,
      dst,
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
  }

  String _slotText(OsgSlot slot) => switch (slot.textSource) {
    OsgTextSource.fixed => slot.fixedText,
    OsgTextSource.annotation => annotationsText,
    OsgTextSource.semantic => slot.semanticTypeId == null
        ? ""
        : (semanticTextByTypeId[slot.semanticTypeId!] ?? ""),
  };

  void _drawSlotText(ui.Canvas canvas, OsgSlot slot, double fw, double fh) {
    final String text = _slotText(slot);
    if (text.isEmpty) {
      return;
    }
    final OsgNormRect b = slot.box;
    final double sl = b.x * fw;
    final double st = b.y * fh;
    final double sw = b.width * fw;
    final double sh = b.height * fh;
    if (sw <= 0 || sh <= 0) {
      return;
    }

    // Same clamp formula as OsgPlayoutLayer.
    final double largestClamp = math.max(fh * 0.25, 6.0);
    final double fontPx = (slot.fontSizeNorm * fh).clamp(6.0, largestClamp);
    final String? ff = slot.fontFamily;

    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: ui.Color(slot.textColorArgb),
          fontSize: fontPx,
          fontFamily: ff == null || ff.isEmpty ? null : ff,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: switch (slot.textAlign) {
        OsgSlotTextAlign.left => TextAlign.left,
        OsgSlotTextAlign.center => TextAlign.center,
        OsgSlotTextAlign.right => TextAlign.right,
      },
      maxLines: switch (slot.textSource) {
        OsgTextSource.annotation => 12,
        OsgTextSource.fixed => 12,
        OsgTextSource.semantic => 3,
      },
      ellipsis: "\u2026",
    );
    painter.layout(maxWidth: sw);

    // Approximate FittedBox.scaleDown: shrink uniformly if the laid-out text
    // overflows the slot box.
    final double scale = math.min(
      1.0,
      math.min(
        painter.width <= 0 ? 1.0 : sw / painter.width,
        painter.height <= 0 ? 1.0 : sh / painter.height,
      ),
    );
    final double drawnW = painter.width * scale;
    final double drawnH = painter.height * scale;

    final double alignX = switch (slot.textAlign) {
      OsgSlotTextAlign.left => 0.0,
      OsgSlotTextAlign.center => 0.5,
      OsgSlotTextAlign.right => 1.0,
    };
    final double alignY = switch (slot.verticalAlign) {
      OsgSlotVerticalAlign.top => 0.0,
      OsgSlotVerticalAlign.center => 0.5,
      OsgSlotVerticalAlign.bottom => 1.0,
    };
    final double dx = sl + (sw - drawnW) * alignX;
    final double dy = st + (sh - drawnH) * alignY;

    canvas.save();
    canvas.translate(dx, dy);
    if (scale < 1.0) {
      canvas.scale(scale);
    }
    painter.paint(canvas, ui.Offset.zero);
    canvas.restore();
    painter.dispose();
  }
}
