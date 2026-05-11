import "dart:async";
import "dart:io";

import "package:flutter/material.dart";
import "package:path/path.dart" as p;

import "package:obs_clipshow/src/features/osg/osg_slot_text_align.dart";
import "package:obs_clipshow/src/features/playout/playout_clip.dart";
import "package:obs_clipshow/src/osg/osg_models.dart";

typedef OsgSemanticResolve = Future<String?> Function(int semanticTypeId);

/// Renders up to three OSG presets in normalized 0..1 coordinates over the canvas.
class OsgPlayoutLayer extends StatefulWidget {
  const OsgPlayoutLayer({
    super.key,
    required this.clip,
    required this.config,
    required this.workspaceRoot,
    required this.resolveSemantic,
    required this.visible,
  });

  final PlayoutClip clip;
  final OsgWorkspaceConfig config;
  final String workspaceRoot;
  final OsgSemanticResolve resolveSemantic;
  final List<bool> visible;

  @override
  State<OsgPlayoutLayer> createState() => _OsgPlayoutLayerState();
}

class _OsgPlayoutLayerState extends State<OsgPlayoutLayer> {
  final Map<int, String> _semanticTextByTypeId = <int, String>{};

  @override
  void didUpdateWidget(covariant OsgPlayoutLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clip.mediaId != widget.clip.mediaId ||
        oldWidget.clip.mediaType != widget.clip.mediaType ||
        oldWidget.clip.semanticTagSnapshotVersion !=
            widget.clip.semanticTagSnapshotVersion) {
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
    for (final OsgPreset pr in widget.config.threePresets) {
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
    final List<OsgPreset> presets = widget.config.threePresets;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        for (int i = 0; i < 3; i++)
          _OsgSinglePresetLayer(
            preset: presets[i],
            visible: i < widget.visible.length ? widget.visible[i] : false,
            workspaceRoot: widget.workspaceRoot,
            semanticTextByTypeId: _semanticTextByTypeId,
            clip: widget.clip,
          ),
      ],
    );
  }
}

class _OsgSinglePresetLayer extends StatelessWidget {
  const _OsgSinglePresetLayer({
    required this.preset,
    required this.visible,
    required this.workspaceRoot,
    required this.semanticTextByTypeId,
    required this.clip,
  });

  final OsgPreset preset;
  final bool visible;
  final String workspaceRoot;
  final Map<int, String> semanticTextByTypeId;
  final PlayoutClip clip;

  static bool _canRenderImage(OsgPreset preset, String workspaceRoot) {
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
  Widget build(BuildContext context) {
    if (!preset.enabled) {
      return const SizedBox.shrink();
    }
    final bool useSolid =
        preset.templateBackgroundKind == OsgTemplateBackgroundKind.solid;
    final bool imageOk =
        !useSolid && _canRenderImage(preset, workspaceRoot);
    if (!useSolid && !imageOk) {
      return const SizedBox.shrink();
    }
    final String? absPath = !useSolid && imageOk
        ? p.normalize(
            p.join(
              p.absolute(workspaceRoot.trim()),
              preset.templateRelativePath
                  .trim()
                  .replaceAll("/", p.separator),
            ),
          )
        : null;

    final double layerOp = preset.layerOpacity.clamp(0.0, 1.0);
    final double animOpacity = visible ? layerOp : 0.0;

    return IgnorePointer(
      ignoring: true,
      child: AnimatedOpacity(
        opacity: animOpacity,
        duration: const Duration(milliseconds: 240),
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
                          OsgTextSource.annotation => clip.annotationsText,
                          OsgTextSource.semantic =>
                            slot.semanticTypeId == null
                                ? ""
                                : (semanticTextByTypeId[slot.semanticTypeId!] ??
                                    ""),
                        };
                        final double fontPx = (slot.fontSizeNorm * fh).clamp(
                          6.0,
                          fh * 0.25,
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
                                maxLines: slot.textSource == OsgTextSource.annotation
                                    ? 12
                                    : 3,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Color(slot.textColorArgb),
                                  fontSize: fontPx,
                                  fontFamily: ff == null || ff.isEmpty
                                      ? null
                                      : ff,
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
                          ),
                        );
                      }),
              ],
            );
            return Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                Positioned(
                  left: left,
                  top: top,
                  width: fw,
                  height: fh,
                  child: cornerR <= 0
                      ? templateStack
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(cornerR),
                          clipBehavior: Clip.antiAlias,
                          child: templateStack,
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
