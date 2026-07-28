import "dart:async";
import "dart:io";
import "dart:math";

import "package:flutter/material.dart";
import "package:path/path.dart" as p;

import "package:obs_clipshow/src/features/osg/osg_slot_text_align.dart";
import "package:obs_clipshow/src/media/media_list_item.dart";
import "package:obs_clipshow/src/osg/osg_models.dart";
import "package:obs_clipshow/src/osg/osg_visibility_motion.dart";

typedef OsgSemanticResolve = Future<String?> Function(int semanticTypeId);

/// Applies visibility motion without [Opacity] / [Transform] when they would be no-ops.
Widget osgWrapVisibilityMotion({
  required ({double opacity, Offset offset}) vis,
  required Widget child,
}) {
  final double opacity = vis.opacity.clamp(0.0, 1.0);
  if (opacity <= 0) {
    return const SizedBox.shrink();
  }
  Widget result = child;
  if (vis.offset != Offset.zero) {
    result = Transform.translate(offset: vis.offset, child: result);
  }
  if (opacity < 1.0) {
    result = Opacity(opacity: opacity, child: result);
  }
  return result;
}

/// Renders up to five OSG presets in normalized 0..1 coordinates over the canvas.
class OsgPlayoutLayer extends StatefulWidget {
  const OsgPlayoutLayer({
    super.key,
    required this.mediaType,
    required this.mediaId,
    required this.annotationsText,
    this.semanticTagSnapshotVersion = 0,
    required this.config,
    required this.workspaceRoot,
    required this.resolveSemantic,
    required this.visible,
  });

  final MediaListItemType mediaType;
  final int mediaId;
  final String annotationsText;
  final int semanticTagSnapshotVersion;
  final OsgWorkspaceConfig config;
  final String workspaceRoot;
  final OsgSemanticResolve resolveSemantic;
  final OsgPresetVisibility visible;

  @override
  State<OsgPlayoutLayer> createState() => _OsgPlayoutLayerState();
}

class _OsgPlayoutLayerState extends State<OsgPlayoutLayer> {
  final Map<int, String> _semanticTextByTypeId = <int, String>{};

  @override
  void didUpdateWidget(covariant OsgPlayoutLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mediaId != widget.mediaId ||
        oldWidget.mediaType != widget.mediaType ||
        oldWidget.semanticTagSnapshotVersion != widget.semanticTagSnapshotVersion) {
      _semanticTextByTypeId.clear();
      unawaited(_loadSemantics());
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadSemantics());
  }

  Future<void> _loadSemantics() async {
    final Set<int> ids = <int>{};
    for (final OsgPreset pr in widget.config.workspacePresets) {
      for (final OsgSlot slot in pr.slots) {
        if (slot.textSource == OsgTextSource.semantic &&
            slot.semanticTypeId != null) {
          ids.add(slot.semanticTypeId!);
        }
      }
    }
    for (final int id in ids) {
      final String? text = await widget.resolveSemantic(id);
      if (!mounted) {
        return;
      }
      setState(() {
        _semanticTextByTypeId[id] = text ?? "";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<OsgPreset> presets = widget.config.workspacePresets;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        for (final OsgPresetSlot slot in OsgPresetSlot.values)
          _OsgSinglePresetLayer(
            preset: presets[slot.presetIndex],
            visible: widget.visible[slot],
            workspaceRoot: widget.workspaceRoot,
            semanticTextByTypeId: _semanticTextByTypeId,
            annotationsText: widget.annotationsText,
          ),
      ],
    );
  }
}

class _OsgSinglePresetLayer extends StatefulWidget {
  const _OsgSinglePresetLayer({
    required this.preset,
    required this.visible,
    required this.workspaceRoot,
    required this.semanticTextByTypeId,
    required this.annotationsText,
  });

  final OsgPreset preset;
  final bool visible;
  final String workspaceRoot;
  final Map<int, String> semanticTextByTypeId;
  final String annotationsText;

  static bool canRenderImage(OsgPreset preset, String workspaceRoot) {
    if (workspaceRoot.trim().isEmpty) {
      return false;
    }
    final String rel = preset.templateRelativePath.trim();
    if (rel.isEmpty) {
      return false;
    }
    final String absPath = p.normalize(
      p.join(
        p.absolute(workspaceRoot.trim()),
        rel.replaceAll("/", p.separator),
      ),
    );
    if (!p.isAbsolute(absPath)) {
      return false;
    }
    return File(absPath).existsSync();
  }

  @override
  State<_OsgSinglePresetLayer> createState() => _OsgSinglePresetLayerState();
}

class _OsgSinglePresetLayerState extends State<_OsgSinglePresetLayer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _entering = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds: OsgPreset.clampVisibilityDurationMs(
          widget.preset.visibilityEnterDurationMs,
        ),
      ),
      value: widget.visible ? 1.0 : 0.0,
    );
    _entering = widget.visible;
    _controller.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void didUpdateWidget(covariant _OsgSinglePresetLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible) {
      if (widget.visible) {
        _entering = true;
        _controller.duration = Duration(
          milliseconds: OsgPreset.clampVisibilityDurationMs(
            widget.preset.visibilityEnterDurationMs,
          ),
        );
        _controller.forward(from: _controller.value);
      } else {
        _entering = false;
        _controller.duration = Duration(
          milliseconds: OsgPreset.clampVisibilityDurationMs(
            widget.preset.visibilityExitDurationMs,
          ),
        );
        _controller.reverse(from: _controller.value);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final OsgPreset preset = widget.preset;
    if (!preset.enabled) {
      return const SizedBox.shrink();
    }
    final bool useSolid =
        preset.templateBackgroundKind == OsgTemplateBackgroundKind.solid;
    final bool imageOk =
        !useSolid && _OsgSinglePresetLayer.canRenderImage(preset, widget.workspaceRoot);
    if (!useSolid && !imageOk) {
      return const SizedBox.shrink();
    }
    if (!widget.visible && _controller.value == 0) {
      return const SizedBox.shrink();
    }
    final String? absPath = !useSolid && imageOk
        ? p.normalize(
            p.join(
              p.absolute(widget.workspaceRoot.trim()),
              preset.templateRelativePath
                  .trim()
                  .replaceAll("/", p.separator),
            ),
          )
        : null;

    final double layerOp = preset.layerOpacity.clamp(0.0, 1.0);

    return IgnorePointer(
      ignoring: true,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) {
          final double w = c.maxWidth;
          final double h = c.maxHeight;
          final OsgNormRect fr = preset.frame;
          final double left = fr.x * w;
          final double top = fr.y * h;
          final double fw = fr.width * w;
          final double fh = fr.height * h;
          final double cornerR = preset.templateCornerRadiusPx(fw, fh);
          final ({double opacity, Offset offset}) vis =
              osgVisibilityOpacityAndOffset(
                entering: _entering,
                shown: _controller.value,
                layerOpacity: layerOp,
                enterMotion: preset.visibilityEnterMotion,
                enterSlideDistanceNorm: preset.visibilityEnterSlideDistanceNorm,
                exitMotion: preset.visibilityExitMotion,
                exitSlideDistanceNorm: preset.visibilityExitSlideDistanceNorm,
                frameWidthPx: fw,
                frameHeightPx: fh,
                enterDurationMs: preset.visibilityEnterDurationMs,
                exitDurationMs: preset.visibilityExitDurationMs,
                enterFadeDurationMs: preset.visibilityEnterFadeDurationMs,
                exitFadeDurationMs: preset.visibilityExitFadeDurationMs,
              );
          final Widget templateStack = Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Positioned.fill(
                child: useSolid
                    ? ColoredBox(color: Color(preset.templateSolidArgb))
                    : Image.file(
                        File(absPath!),
                        fit: BoxFit.cover,
                        alignment: Alignment.center,
                        gaplessPlayback: true,
                      ),
              ),
              ...preset.slots.map((OsgSlot slot) {
                final OsgNormRect b = slot.box;
                final double sl = b.x * fw;
                final double st = b.y * fh;
                final double sw = b.width * fw;
                final double sh = b.height * fh;
                final String text = switch (slot.textSource) {
                  OsgTextSource.fixed => slot.fixedText,
                  OsgTextSource.annotation => widget.annotationsText,
                  OsgTextSource.semantic =>
                    slot.semanticTypeId == null
                        ? ""
                        : (widget.semanticTextByTypeId[slot.semanticTypeId!] ??
                            ""),
                };
                final largestClamp = max(fh * 0.25, 6.0);
                final double fontPx = (slot.fontSizeNorm * fh).clamp(
                  6.0,
                  largestClamp,
                );
                final String? ff = slot.fontFamily;
                return Positioned(
                  left: sl,
                  top: st,
                  width: sw,
                  height: sh,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: osgSlotAlignment(
                      slot.textAlign,
                      slot.verticalAlign,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: sw,
                        maxHeight: sh,
                      ),
                      child: Text(
                        text,
                        textAlign: osgSlotTextAlignToFlutterTextAlign(
                          slot.textAlign,
                        ),
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
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          );
          final Widget graphic = cornerR <= 0
              ? templateStack
              : ClipRRect(
                  borderRadius: BorderRadius.circular(cornerR),
                  clipBehavior: Clip.antiAlias,
                  child: templateStack,
                );
          return Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Positioned(
                left: left,
                top: top,
                width: fw,
                height: fh,
                child: osgWrapVisibilityMotion(vis: vis, child: graphic),
              ),
            ],
          );
        },
      ),
    );
  }
}
