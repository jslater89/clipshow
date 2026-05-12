import "package:flutter/material.dart";

import "package:obs_clipshow/src/app/ui_scale.dart";
import "package:obs_clipshow/src/features/osg/osg_editor_geometry.dart";
import "package:obs_clipshow/src/osg/osg_models.dart";

/// How [OsgScaledRectFields] shows and parses x, y, width, height.
enum OsgRectFieldDisplayMode {
  /// Playout canvas pixels (frame on screen).
  canvasPixels,

  /// Graphic-local 0–1 ratios as percentages (e.g. `45.1` → 45.1%). For template text slots.
  graphicPercent,
}

/// Rounds [v] for display; keeps values readable on large canvases.
int osgDisplayPixel(int v) {
  return v.clamp(0, 99999);
}

/// Like [osgDisplayPixel] but allows negative coordinates when the playout frame extends past the canvas.
int osgDisplayPixelSigned(int v) {
  return v.clamp(-999999, 999999);
}

/// One decimal place; value is 0–100, not 0–1 (use for text fields without a "%" suffix).
String osgFormatGraphicPercent(double norm) {
  return (norm * 100).toStringAsFixed(1);
}

/// Parses a percentage field into 0–1; optional trailing `%` is ignored.
double osgParseGraphicPercentField(String raw) {
  String t = raw.trim();
  if (t.endsWith("%")) {
    t = t.substring(0, t.length - 1).trim();
  }
  return ((double.tryParse(t) ?? 0) / 100).clamp(0.0, 1.0);
}

({int x, int y, int w, int h}) osgNormFrameToCanvasPixels(
  OsgNormRect r,
  int canvasW,
  int canvasH,
) {
  final double cw = canvasW.toDouble();
  final double ch = canvasH.toDouble();
  return (
    x: osgDisplayPixelSigned((r.x * cw).round()),
    y: osgDisplayPixelSigned((r.y * ch).round()),
    w: osgDisplayPixel((r.width * cw).round()),
    h: osgDisplayPixel((r.height * ch).round()),
  );
}

OsgNormRect osgCanvasPixelsToNormFrame(
  int xPx,
  int yPx,
  int wPx,
  int hPx,
  int canvasW,
  int canvasH,
) {
  final double cw = canvasW.toDouble();
  final double ch = canvasH.toDouble();
  return osgClampFrameForPlayout(
    OsgNormRect(
      x: xPx / cw,
      y: yPx / ch,
      width: (wPx / cw).clamp(0.0, 1.0),
      height: (hPx / ch).clamp(0.0, 1.0),
    ),
  );
}

({int x, int y, int w, int h}) osgSlotGraphicLocalToCanvasPixels(
  OsgNormRect slot,
  OsgNormRect frame,
  int canvasW,
  int canvasH,
) {
  final double cw = canvasW.toDouble();
  final double ch = canvasH.toDouble();
  final double fx = frame.x * cw;
  final double fy = frame.y * ch;
  final double fw = frame.width * cw;
  final double fh = frame.height * ch;
  final double x = fx + slot.x * fw;
  final double y = fy + slot.y * fh;
  final double w = slot.width * fw;
  final double h = slot.height * fh;
  return (
    x: osgDisplayPixelSigned(x.round()),
    y: osgDisplayPixelSigned(y.round()),
    w: osgDisplayPixel(w.round()),
    h: osgDisplayPixel(h.round()),
  );
}

OsgNormRect osgCanvasPixelsToSlotGraphicLocal(
  int xPx,
  int yPx,
  int wPx,
  int hPx,
  OsgNormRect frame,
  int canvasW,
  int canvasH,
) {
  final double cw = canvasW.toDouble();
  final double ch = canvasH.toDouble();
  final double fx = frame.x * cw;
  final double fy = frame.y * ch;
  final double fw = frame.width * cw;
  final double fh = frame.height * ch;
  if (fw < 1e-6 || fh < 1e-6) {
    return const OsgNormRect(x: 0, y: 0, width: 0.02, height: 0.02);
  }
  return osgClampSlotBox(
    OsgNormRect(
      x: ((xPx - fx) / fw).clamp(0.0, 1.0),
      y: ((yPx - fy) / fh).clamp(0.0, 1.0),
      width: (wPx / fw).clamp(0.02, 1.0),
      height: (hPx / fh).clamp(0.02, 1.0),
    ),
  );
}

/// Edits a rectangle; [displayMode] selects canvas pixels vs graphic-local percentages.
class OsgScaledRectFields extends StatefulWidget {
  const OsgScaledRectFields({
    super.key,
    this.displayMode = OsgRectFieldDisplayMode.canvasPixels,
    required this.canvasWidth,
    required this.canvasHeight,
    required this.normRect,
    required this.onNormChanged,
    required this.label,
    required this.isSlotInFrame,
    this.frame,
  }) : assert(
          displayMode == OsgRectFieldDisplayMode.graphicPercent ||
              !isSlotInFrame ||
              frame != null,
          "Canvas-pixel slot editing requires a non-null frame.",
        );

  final OsgRectFieldDisplayMode displayMode;
  final int canvasWidth;
  final int canvasHeight;
  final OsgNormRect normRect;
  final ValueChanged<OsgNormRect> onNormChanged;
  final String label;
  final bool isSlotInFrame;
  final OsgNormRect? frame;

  @override
  State<OsgScaledRectFields> createState() => _OsgScaledRectFieldsState();
}

class _OsgScaledRectFieldsState extends State<OsgScaledRectFields> {
  late final TextEditingController _x;
  late final TextEditingController _y;
  late final TextEditingController _w;
  late final TextEditingController _h;
  final FocusNode _fx = FocusNode();
  final FocusNode _fy = FocusNode();
  final FocusNode _fw = FocusNode();
  final FocusNode _fh = FocusNode();

  @override
  void initState() {
    super.initState();
    _x = TextEditingController();
    _y = TextEditingController();
    _w = TextEditingController();
    _h = TextEditingController();
    _applyNormToControllers();
  }

  bool get _anyFocused =>
      _fx.hasFocus || _fy.hasFocus || _fw.hasFocus || _fh.hasFocus;

  void _applyNormToControllers({OsgNormRect? norm}) {
    final OsgNormRect r = norm ?? widget.normRect;
    if (widget.displayMode == OsgRectFieldDisplayMode.graphicPercent) {
      _x.text = osgFormatGraphicPercent(r.x);
      _y.text = osgFormatGraphicPercent(r.y);
      _w.text = osgFormatGraphicPercent(r.width);
      _h.text = osgFormatGraphicPercent(r.height);
      return;
    }
    final ({int x, int y, int w, int h}) p = _pixelsFromNormFor(r);
    _x.text = "${p.x}";
    _y.text = "${p.y}";
    _w.text = "${p.w}";
    _h.text = "${p.h}";
  }

  ({int x, int y, int w, int h}) _pixelsFromNormFor(OsgNormRect norm) {
    if (widget.isSlotInFrame) {
      return osgSlotGraphicLocalToCanvasPixels(
        norm,
        widget.frame!,
        widget.canvasWidth,
        widget.canvasHeight,
      );
    }
    return osgNormFrameToCanvasPixels(
      norm,
      widget.canvasWidth,
      widget.canvasHeight,
    );
  }

  @override
  void didUpdateWidget(covariant OsgScaledRectFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool normChanged = oldWidget.normRect != widget.normRect;
    final bool ctxChanged =
        oldWidget.frame != widget.frame ||
        oldWidget.canvasWidth != widget.canvasWidth ||
        oldWidget.canvasHeight != widget.canvasHeight ||
        oldWidget.displayMode != widget.displayMode;
    if ((normChanged || ctxChanged) && !_anyFocused) {
      _applyNormToControllers();
    }
  }

  @override
  void dispose() {
    _x.dispose();
    _y.dispose();
    _w.dispose();
    _h.dispose();
    _fx.dispose();
    _fy.dispose();
    _fw.dispose();
    _fh.dispose();
    super.dispose();
  }

  int _parseClamped(String raw, int maxPx) {
    final int v = int.tryParse(raw.trim()) ?? 0;
    return v.clamp(0, maxPx);
  }

  int _parseSignedAxis(String raw, int canvasLen) {
    final int? v = int.tryParse(raw.trim());
    if (v == null) {
      return 0;
    }
    return v.clamp(-canvasLen * 4, canvasLen * 4);
  }

  void _emit() {
    if (widget.displayMode == OsgRectFieldDisplayMode.graphicPercent) {
      final double nx = osgParseGraphicPercentField(_x.text);
      final double ny = osgParseGraphicPercentField(_y.text);
      final double nw = osgParseGraphicPercentField(_w.text);
      final double nh = osgParseGraphicPercentField(_h.text);
      final OsgNormRect raw = OsgNormRect(
        x: nx,
        y: ny,
        width: nw,
        height: nh,
      );
      final OsgNormRect clamped = widget.isSlotInFrame
          ? osgClampSlotBox(raw)
          : osgClampFrameForPlayout(raw);
      widget.onNormChanged(clamped);
      if (!_anyFocused) {
        _applyNormToControllers(norm: clamped);
      }
      return;
    }
    final int cw = widget.canvasWidth;
    final int ch = widget.canvasHeight;
    final int xPx = widget.isSlotInFrame
        ? _parseClamped(_x.text, cw)
        : _parseSignedAxis(_x.text, cw);
    final int yPx = widget.isSlotInFrame
        ? _parseClamped(_y.text, ch)
        : _parseSignedAxis(_y.text, ch);
    final int wPx = _parseClamped(_w.text, cw).clamp(1, cw);
    final int hPx = _parseClamped(_h.text, ch).clamp(1, ch);
    if (widget.isSlotInFrame) {
      final OsgNormRect next = osgCanvasPixelsToSlotGraphicLocal(
        xPx,
        yPx,
        wPx,
        hPx,
        widget.frame!,
        cw,
        ch,
      );
      widget.onNormChanged(next);
      if (!_anyFocused) {
        _applyNormToControllers(norm: next);
      }
    } else {
      widget.onNormChanged(
        osgCanvasPixelsToNormFrame(xPx, yPx, wPx, hPx, cw, ch),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final double gap = scaleDimension(context, 4);
    final double fieldW = scaleDimension(context, 56);
    final double fieldH = scaleDimension(context, 40);
    final bool pct = widget.displayMode == OsgRectFieldDisplayMode.graphicPercent;
    final String helper = pct
        ? "Relative to template graphic (percent of width/height)."
        : "Values in playout canvas pixels (${widget.canvasWidth}×${widget.canvasHeight}).";
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(widget.label, style: Theme.of(context).textTheme.labelLarge),
        Text(helper, style: Theme.of(context).textTheme.bodySmall),
        SizedBox(height: gap),
        Row(
          children: <Widget>[
            SizedBox(
              width: fieldW,
              height: fieldH,
              child: TextField(
                controller: _x,
                focusNode: _fx,
                keyboardType: pct
                    ? const TextInputType.numberWithOptions(decimal: true)
                    : TextInputType.number,
                maxLength: pct ? 8 : 5,
                buildCounter: (
                  BuildContext c, {
                  required int currentLength,
                  required bool isFocused,
                  required int? maxLength,
                }) =>
                    null,
                decoration: InputDecoration(
                  labelText: pct ? "x %" : "x",
                  isDense: true,
                  suffixText: pct ? "%" : null,
                ),
                onEditingComplete: _emit,
                onSubmitted: (_) => _emit(),
              ),
            ),
            SizedBox(width: gap),
            SizedBox(
              width: fieldW,
              height: fieldH,
              child: TextField(
                controller: _y,
                focusNode: _fy,
                keyboardType: pct
                    ? const TextInputType.numberWithOptions(decimal: true)
                    : TextInputType.number,
                maxLength: pct ? 8 : 5,
                buildCounter: (
                  BuildContext c, {
                  required int currentLength,
                  required bool isFocused,
                  required int? maxLength,
                }) =>
                    null,
                decoration: InputDecoration(
                  labelText: pct ? "y %" : "y",
                  isDense: true,
                  suffixText: pct ? "%" : null,
                ),
                onEditingComplete: _emit,
                onSubmitted: (_) => _emit(),
              ),
            ),
            SizedBox(width: gap),
            SizedBox(
              width: fieldW,
              height: fieldH,
              child: TextField(
                controller: _w,
                focusNode: _fw,
                keyboardType: pct
                    ? const TextInputType.numberWithOptions(decimal: true)
                    : TextInputType.number,
                maxLength: pct ? 8 : 5,
                buildCounter: (
                  BuildContext c, {
                  required int currentLength,
                  required bool isFocused,
                  required int? maxLength,
                }) =>
                    null,
                decoration: InputDecoration(
                  labelText: pct ? "w %" : "w",
                  isDense: true,
                  suffixText: pct ? "%" : null,
                ),
                onEditingComplete: _emit,
                onSubmitted: (_) => _emit(),
              ),
            ),
            SizedBox(width: gap),
            SizedBox(
              width: fieldW,
              height: fieldH,
              child: TextField(
                controller: _h,
                focusNode: _fh,
                keyboardType: pct
                    ? const TextInputType.numberWithOptions(decimal: true)
                    : TextInputType.number,
                maxLength: pct ? 8 : 5,
                buildCounter: (
                  BuildContext c, {
                  required int currentLength,
                  required bool isFocused,
                  required int? maxLength,
                }) =>
                    null,
                decoration: InputDecoration(
                  labelText: pct ? "h %" : "h",
                  isDense: true,
                  suffixText: pct ? "%" : null,
                ),
                onEditingComplete: _emit,
                onSubmitted: (_) => _emit(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Alias for [OsgScaledRectFields] (same constructor; [OsgRectFieldDisplayMode] defaults to canvas pixels).
typedef OsgScaledCanvasRectFields = OsgScaledRectFields;
