import "dart:io";

import "package:flutter/material.dart";
import "package:path/path.dart" as p;

import "package:obs_clipshow/src/features/osg/osg_editor_geometry.dart";
import "package:obs_clipshow/src/features/osg/osg_slot_text_align.dart";
import "package:obs_clipshow/src/osg/osg_models.dart";
import "package:obs_clipshow/src/osg/osg_visibility_motion.dart";
import "package:obs_clipshow/src/widgets/checkerboard_background.dart";

/// How the user may interact with the preview.
enum OsgEditorPreviewInteraction {
  /// Drag the template [OsgPreset.frame] on the full canvas; resize preserves image aspect.
  frame,

  /// Drag and resize text slots in **graphic-local** 0..1 space (isolation view only).
  slots,
}

/// Letterboxed playout canvas (screen mode) or graphic-local board (isolation mode).
class OsgPresetCanvasPreview extends StatefulWidget {
  const OsgPresetCanvasPreview({
    super.key,
    required this.playoutOutputSize,
    required this.workspaceRoot,
    required this.preset,
    required this.interaction,
    required this.graphicLocalLayout,
    this.onFrameChanged,
    this.onSlotChanged,
    this.dimOutsideFrame = false,
    this.applyLayerOpacity = true,
    this.semanticTypeNamesById,
    this.motionPreviewSample,
  });

  final PlayoutOutputSize playoutOutputSize;
  final String workspaceRoot;
  final OsgPreset preset;

  /// When set, applies the same enter/exit opacity + slide as playout on the frame.
  final OsgMotionPreviewSample? motionPreviewSample;

  /// When set, semantic slots show these names instead of raw ids in preview text.
  final Map<int, String>? semanticTypeNamesById;
  final OsgEditorPreviewInteraction interaction;

  /// When true, the preview is only the template aspect box (slots 0..1 in graphic space).
  final bool graphicLocalLayout;

  final ValueChanged<OsgNormRect>? onFrameChanged;
  final void Function(int slotIndex, OsgSlot slot)? onSlotChanged;
  final bool dimOutsideFrame;

  /// When true, multiplies [OsgPreset.layerOpacity] over the graphic (screen preview).
  /// Isolation preview sets this false so per-pixel alphas show without the layer fade.
  final bool applyLayerOpacity;

  @override
  State<OsgPresetCanvasPreview> createState() => _OsgPresetCanvasPreviewState();
}

class _OsgPresetCanvasPreviewState extends State<OsgPresetCanvasPreview> {
  OsgNormRect? _framePanStart;
  Offset _framePanAccum = Offset.zero;

  OsgNormRect? _frameResizeStart;
  Offset _frameResizeAccum = Offset.zero;

  int? _slotDragIndex;
  OsgNormRect? _slotPanStart;
  Offset _slotPanAccum = Offset.zero;

  int? _slotResizeIndex;
  OsgNormRect? _slotResizeStart;
  Offset _slotResizeAccum = Offset.zero;

  static const double _handleSize = 14;
  String? get _absTemplatePath {
    final String rel = widget.preset.templateRelativePath.trim();
    if (rel.isEmpty) {
      return null;
    }
    final String root = widget.workspaceRoot.trim();
    if (root.isEmpty) {
      return null;
    }
    final String absPath = p.normalize(
      p.join(p.absolute(root), rel.replaceAll("/", p.separator)),
    );
    if (!p.isAbsolute(absPath)) {
      return null;
    }
    final File f = File(absPath);
    if (!f.existsSync()) {
      return null;
    }
    return absPath;
  }

  double get _imageAspect => widget.preset.templateAspectRatioForFrame;

  /// Checkerboard and frame border; lives under preview gesture stacks.
  List<Widget> _previewBoardUnderlay() {
    return <Widget>[
      const Positioned.fill(child: CheckerboardBackground()),
      Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white24, width: 2),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (widget.graphicLocalLayout) {
      return _buildGraphicLocalBoard(context);
    }
    final PlayoutOutputSize po = widget.playoutOutputSize;
    if (!po.isValid) {
      return const Center(child: Text("Invalid playout size."));
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final double aspect = po.aspectRatio;
        double pw = c.maxWidth;
        double ph = pw / aspect;
        if (ph > c.maxHeight && c.maxHeight.isFinite) {
          ph = c.maxHeight;
          pw = ph * aspect;
        }
        final double playoutAspect = pw / ph;
        return Center(
          child: SizedBox(
            width: pw,
            height: ph,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: <Widget>[
                  ..._previewBoardUnderlay(),
                  if (widget.dimOutsideFrame)
                    CustomPaint(
                      size: Size(pw, ph),
                      painter: _OsgFrameDimPainter(frame: widget.preset.frame),
                    ),
                  Opacity(
                    opacity: widget.motionPreviewSample != null
                        ? 1.0
                        : (widget.applyLayerOpacity
                              ? widget.preset.layerOpacity.clamp(0.0, 1.0)
                              : 1.0),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: _buildScreenLayers(pw, ph, playoutAspect),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGraphicLocalBoard(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final double imgAsp = _imageAspect;
        double pw = c.maxWidth;
        double ph = pw / imgAsp;
        if (ph > c.maxHeight && c.maxHeight.isFinite) {
          ph = c.maxHeight;
          pw = ph * imgAsp;
        }
        final double cornerIso =
            widget.preset.templateCornerRadiusPx(pw, ph);
        final Widget isoGraphic = Stack(
          clipBehavior: Clip.none,
          children: _buildGraphicStackChildren(
            pw,
            ph,
            canvasPw: pw,
            canvasPh: ph,
            includeFrameGestures: false,
            includeSlotGestures:
                widget.interaction == OsgEditorPreviewInteraction.slots,
          ),
        );
        return Center(
          child: SizedBox(
            width: pw,
            height: ph,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: <Widget>[
                  ..._previewBoardUnderlay(),
                  Opacity(
                    opacity: widget.applyLayerOpacity
                        ? widget.preset.layerOpacity.clamp(0.0, 1.0)
                        : 1.0,
                    child: cornerIso <= 0
                        ? isoGraphic
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(cornerIso),
                            clipBehavior: Clip.antiAlias,
                            child: isoGraphic,
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildScreenLayers(double pw, double ph, double playoutAspect) {
    final OsgPreset preset = widget.preset;
    final OsgNormRect fr = preset.frame;
    final double left = fr.x * pw;
    final double top = fr.y * ph;
    final double fw = fr.width * pw;
    final double fh = fr.height * ph;
    final double cornerR = preset.templateCornerRadiusPx(fw, fh);

    final Widget frameStack = Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        ..._buildGraphicStackChildren(
          fw,
          fh,
          canvasPw: pw,
          canvasPh: ph,
          includeFrameGestures:
              widget.onFrameChanged != null &&
              widget.interaction == OsgEditorPreviewInteraction.frame,
          includeSlotGestures: false,
        ),
        ..._buildSlotOverlaysInFrame(fw, fh),
      ],
    );

    final OsgMotionPreviewSample? mp = widget.motionPreviewSample;
    final Widget clippedGraphic = cornerR <= 0
        ? frameStack
        : ClipRRect(
            borderRadius: BorderRadius.circular(cornerR),
            clipBehavior: Clip.antiAlias,
            child: frameStack,
          );

    Widget graphicAndBorder = Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: <Widget>[
        Positioned.fill(child: clippedGraphic),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: cornerR > 0
                    ? BorderRadius.circular(cornerR)
                    : null,
                border: Border.all(color: Colors.amberAccent, width: 1),
              ),
            ),
          ),
        ),
      ],
    );

    if (mp != null) {
      final double lo = preset.layerOpacity.clamp(0.0, 1.0);
      final ({double opacity, Offset offset}) vis = osgVisibilityOpacityAndOffset(
        entering: mp.isEnterLeg,
        shown: mp.shown,
        layerOpacity: lo,
        enterMotion: preset.visibilityEnterMotion,
        enterSlideDistanceNorm: preset.visibilityEnterSlideDistanceNorm,
        exitMotion: preset.visibilityExitMotion,
        exitSlideDistanceNorm: preset.visibilityExitSlideDistanceNorm,
        frameWidthPx: fw,
        frameHeightPx: fh,
      );
      graphicAndBorder = Opacity(
        opacity: vis.opacity.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: vis.offset,
          child: graphicAndBorder,
        ),
      );
    }

    return <Widget>[
      Positioned(
        left: left,
        top: top,
        width: fw,
        height: fh,
        child: graphicAndBorder,
      ),
      if (widget.interaction == OsgEditorPreviewInteraction.frame &&
          widget.onFrameChanged != null)
        Positioned(
          left: left + fw - _handleSize / 2,
          top: top + fh - _handleSize / 2,
          width: _handleSize,
          height: _handleSize,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) {
              _frameResizeStart = fr;
              _frameResizeAccum = Offset.zero;
            },
            onPanUpdate: (DragUpdateDetails d) {
              final OsgNormRect? start = _frameResizeStart;
              if (start == null) {
                return;
              }
              _frameResizeAccum += d.delta;
              final double nw = start.width + _frameResizeAccum.dx / pw;
              widget.onFrameChanged!(
                osgFrameResizeWidthPreservingAspect(
                  frame: start,
                  newWidth: nw,
                  imageWidthOverHeight: _imageAspect,
                  playoutAspect: playoutAspect,
                ),
              );
            },
            onPanEnd: (_) {
              _frameResizeStart = null;
              _frameResizeAccum = Offset.zero;
            },
            onPanCancel: () {
              _frameResizeStart = null;
              _frameResizeAccum = Offset.zero;
            },
            child: Material(
              color: Colors.lightBlueAccent,
              shape: const CircleBorder(),
              elevation: 2,
              child: const SizedBox.expand(),
            ),
          ),
        ),
    ];
  }

  /// Image + optional frame pan gesture; [fw],[fh] are pixel size of the graphic stack.
  List<Widget> _buildGraphicStackChildren(
    double fw,
    double fh, {
    required double canvasPw,
    required double canvasPh,
    required bool includeFrameGestures,
    required bool includeSlotGestures,
  }) {
    final OsgPreset preset = widget.preset;
    final String? path = _absTemplatePath;
    final bool solid =
        preset.templateBackgroundKind == OsgTemplateBackgroundKind.solid;
    // Match [OsgPlayoutLayer]: template must be [Positioned.fill] so [BoxFit.cover]
    // receives tight constraints; a bare [Stack] child can size to intrinsics and
    // sit at the default top-start, which looks letterboxed and misaligns slots.
    final Widget templateGraphic = solid
        ? ColoredBox(color: Color(preset.templateSolidArgb))
        : path != null
        ? Image.file(
            File(path),
            fit: BoxFit.cover,
            alignment: Alignment.center,
            gaplessPlayback: true,
          )
        : Center(
            child: Text(
              "No template image",
              style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
            ),
          );

    final List<Widget> children = <Widget>[
      Positioned.fill(child: templateGraphic),
      if (includeFrameGestures && widget.onFrameChanged != null)
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) {
              _framePanStart = preset.frame;
              _framePanAccum = Offset.zero;
            },
            onPanUpdate: (DragUpdateDetails d) {
              final OsgNormRect? start = _framePanStart;
              if (start == null) {
                return;
              }
              _framePanAccum += d.delta;
              final double nx = _framePanAccum.dx / canvasPw;
              final double ny = _framePanAccum.dy / canvasPh;
              widget.onFrameChanged!(
                osgClampFrameForPlayout(
                  OsgNormRect(
                    x: start.x + nx,
                    y: start.y + ny,
                    width: start.width,
                    height: start.height,
                  ),
                ),
              );
            },
            onPanEnd: (_) {
              _framePanStart = null;
              _framePanAccum = Offset.zero;
            },
            onPanCancel: () {
              _framePanStart = null;
              _framePanAccum = Offset.zero;
            },
          ),
        ),
    ];

    if (includeSlotGestures && widget.onSlotChanged != null) {
      for (int i = 0; i < preset.slots.length; i++) {
        children.add(_slotInteractiveLayer(fw, fh, i, preset.slots[i]));
      }
    }

    return children;
  }

  List<Widget> _buildSlotOverlaysInFrame(double fw, double fh) {
    return widget.preset.slots.map((OsgSlot slot) {
      final OsgNormRect b = slot.box;
      return Positioned(
        left: b.x * fw,
        top: b.y * fh,
        width: b.width * fw,
        height: b.height * fh,
        child: IgnorePointer(
          child: _slotText(slot, fh, b.width * fw, b.height * fh),
        ),
      );
    }).toList();
  }

  String _semanticSlotPreviewText(OsgSlot slot) {
    final int? id = slot.semanticTypeId;
    if (id == null) {
      return "—";
    }
    final Map<int, String>? names = widget.semanticTypeNamesById;
    if (names != null) {
      final String? n = names[id];
      if (n != null && n.trim().isNotEmpty) {
        return "Tag: ${n.trim()}";
      }
    }
    return "Tag: #$id";
  }

  Widget _slotText(OsgSlot slot, double fh, double sw, double sh) {
    final String text = switch (slot.textSource) {
      OsgTextSource.fixed => slot.fixedText,
      OsgTextSource.semantic => _semanticSlotPreviewText(slot),
      OsgTextSource.annotation => "Annotation",
    };
    final double fontPx = (slot.fontSizeNorm * fh).clamp(6.0, fh * 0.25);
    final String? ff = slot.fontFamily;
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: osgSlotAlignment(slot.textAlign, slot.verticalAlign),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: sw, maxHeight: sh),
        child: Text(
          text,
          textAlign: osgSlotTextAlignToFlutterTextAlign(slot.textAlign),
          maxLines: switch (slot.textSource) {
            OsgTextSource.annotation => 12,
            OsgTextSource.fixed => 12,
            OsgTextSource.semantic => 3,
          },
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Color(slot.textColorArgb),
            fontSize: fontPx,
            fontFamily: ff == null || ff.isEmpty ? null : ff,
            // fontWeight: FontWeight.w600,
            // shadows: const <Shadow>[
            //   Shadow(
            //     offset: Offset(1, 1),
            //     blurRadius: 2,
            //     color: Colors.black87,
            //   ),
            // ],
          ),
        ),
      ),
    );
  }

  Widget _slotInteractiveLayer(
    double fw,
    double fh,
    int slotIndex,
    OsgSlot slot,
  ) {
    final OsgNormRect b = slot.box;
    final double sw = b.width * fw;
    final double sh = b.height * fh;
    // Stack hit testing is limited to layout size even with [Clip.none]; extend
    // the slot box so the bottom-right resize handle (half outside the slot) is
    // fully tappable.
    final double pad = _handleSize / 2;
    return Positioned(
      left: b.x * fw,
      top: b.y * fh,
      width: sw + pad,
      height: sh + pad,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned(
            left: 0,
            top: 0,
            width: sw,
            height: sh,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) {
                _slotDragIndex = slotIndex;
                _slotPanStart = b;
                _slotPanAccum = Offset.zero;
              },
              onPanUpdate: (DragUpdateDetails d) {
                if (_slotDragIndex != slotIndex) {
                  return;
                }
                final OsgNormRect? start = _slotPanStart;
                if (start == null) {
                  return;
                }
                _slotPanAccum += d.delta;
                final double nx = _slotPanAccum.dx / fw;
                final double ny = _slotPanAccum.dy / fh;
                final OsgNormRect next = osgClampSlotBox(
                  OsgNormRect(
                    x: start.x + nx,
                    y: start.y + ny,
                    width: start.width,
                    height: start.height,
                  ),
                );
                widget.onSlotChanged!(
                  slotIndex,
                  slot.copyWith(box: next),
                );
              },
              onPanEnd: (_) {
                if (_slotDragIndex == slotIndex) {
                  _slotDragIndex = null;
                  _slotPanStart = null;
                  _slotPanAccum = Offset.zero;
                }
              },
              onPanCancel: () {
                if (_slotDragIndex == slotIndex) {
                  _slotDragIndex = null;
                  _slotPanStart = null;
                  _slotPanAccum = Offset.zero;
                }
              },
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.amberAccent, width: 1),
                  color: Colors.black26,
                ),
                child: _slotText(slot, fh, sw, sh),
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            width: _handleSize,
            height: _handleSize,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) {
                _slotResizeIndex = slotIndex;
                _slotResizeStart = b;
                _slotResizeAccum = Offset.zero;
              },
              onPanUpdate: (DragUpdateDetails d) {
                if (_slotResizeIndex != slotIndex) {
                  return;
                }
                final OsgNormRect? start = _slotResizeStart;
                if (start == null) {
                  return;
                }
                _slotResizeAccum += d.delta;
                final double nw = start.width + _slotResizeAccum.dx / fw;
                final double nh = start.height + _slotResizeAccum.dy / fh;
                final OsgNormRect next = osgClampSlotBox(
                  OsgNormRect(x: start.x, y: start.y, width: nw, height: nh),
                );
                widget.onSlotChanged!(
                  slotIndex,
                  slot.copyWith(box: next),
                );
              },
              onPanEnd: (_) {
                if (_slotResizeIndex == slotIndex) {
                  _slotResizeIndex = null;
                  _slotResizeStart = null;
                  _slotResizeAccum = Offset.zero;
                }
              },
              onPanCancel: () {
                if (_slotResizeIndex == slotIndex) {
                  _slotResizeIndex = null;
                  _slotResizeStart = null;
                  _slotResizeAccum = Offset.zero;
                }
              },
              child: Material(
                color: Colors.amber,
                shape: const CircleBorder(),
                elevation: 2,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OsgFrameDimPainter extends CustomPainter {
  _OsgFrameDimPainter({required this.frame});

  final OsgNormRect frame;

  @override
  void paint(Canvas canvas, Size size) {
    final double pw = size.width;
    final double ph = size.height;
    final Rect outer = Offset.zero & size;
    final Rect inner = Rect.fromLTWH(
      frame.x * pw,
      frame.y * ph,
      frame.width * pw,
      frame.height * ph,
    );
    final Path p = Path()
      ..addRect(outer)
      ..addRect(inner)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(p, Paint()..color = Colors.black.withValues(alpha: 0.45));
  }

  @override
  bool shouldRepaint(covariant _OsgFrameDimPainter oldDelegate) {
    return oldDelegate.frame != frame;
  }
}
