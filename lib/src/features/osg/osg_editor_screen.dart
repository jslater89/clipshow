import "dart:async";
import "dart:io";
import "dart:typed_data";

import "package:file_picker/file_picker.dart";
import "package:flutter/material.dart";
import "package:path/path.dart" as p;
import "package:provider/provider.dart";
import "package:system_fonts/system_fonts.dart";

import "package:obs_clipshow/src/app/ui_scale.dart";
import "package:obs_clipshow/src/features/dashboard/dashboard_view_model.dart";
import "package:obs_clipshow/src/features/dashboard/widgets/dashboard_shared_helpers.dart";
import "package:obs_clipshow/src/features/osg/osg_editor_geometry.dart";
import "package:obs_clipshow/src/features/osg/osg_editor_pixel_rect.dart";
import "package:obs_clipshow/src/features/osg/osg_template_aspect.dart";
import "package:obs_clipshow/src/features/osg/widgets/osg_preset_canvas_preview.dart";
import "package:obs_clipshow/src/features/osg/widgets/osg_semantic_type_icon_catalog.dart";
import "package:obs_clipshow/src/features/osg/widgets/osg_semantic_type_icon_picker.dart";
import "package:obs_clipshow/src/osg/osg_models.dart";
import "package:obs_clipshow/src/osg/osg_preset_pack_zip.dart";
import "package:obs_clipshow/src/osg/osg_visibility_motion.dart";
import "package:obs_clipshow/src/widgets/rgba_color_picker.dart";
import "package:obs_clipshow/src/workspace/workspace_media_paths.dart";

InputDecoration _osgEditorDenseBorderlessDecoration({
  required String labelText,
  String? helperText,
}) {
  return InputDecoration(
    floatingLabelBehavior: FloatingLabelBehavior.always,
    labelText: labelText,
    helperText: helperText,
    isDense: true,
    border: UnderlineInputBorder()
  );
}

String _osgVisibilityMotionMenuLabel(
  OsgPresetVisibilityMotion m, {
  required bool forExit,
}) {
  switch (m) {
    case OsgPresetVisibilityMotion.none:
      return "Fade Only";
    case OsgPresetVisibilityMotion.left:
      return forExit ? "Fade + To Left" : "Fade + From Left";
    case OsgPresetVisibilityMotion.right:
      return forExit ? "Fade + To Right" : "Fade + From Right";
    case OsgPresetVisibilityMotion.top:
      return forExit ? "Fade + To Top" : "Fade + From Top";
    case OsgPresetVisibilityMotion.bottom:
      return forExit ? "Fade + To Bottom" : "Fade + From Bottom";
  }
}

/// Full-screen editor for semantic types and five OSG presets.
/// Playout canvas size is configured under Workspace Settings.
class OsgEditorScreen extends StatefulWidget {
  const OsgEditorScreen({super.key, required this.workspaceRoot});

  final String workspaceRoot;

  @override
  State<OsgEditorScreen> createState() => _OsgEditorScreenState();
}

class _OsgEditorScreenState extends State<OsgEditorScreen>
    with TickerProviderStateMixin {
  static const int _motionPreviewBetweenMs = 600;

  late OsgWorkspaceConfig _draftOsg;
  late TabController _tabController;
  late AnimationController _motionPreviewSequence;
  final ScrollController _semanticTypesScrollController = ScrollController();
  List<String> _systemFontNames = <String>[];
  bool _systemFontsLoading = true;
  bool _motionPreviewActive = false;
  bool _motionPreviewLoop = false;
  late int _lastTabIndexForMotion;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _lastTabIndexForMotion = _tabController.index;
    final DashboardViewModel vm = context.read<DashboardViewModel>();
    _draftOsg = OsgWorkspaceConfig.decodeFromStorageJson(
      vm.osgWorkspaceConfig.encodeToStorageJson(),
    );
    unawaited(_loadSystemFontNames());
    _motionPreviewSequence = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1080),
    );
    _motionPreviewSequence.addStatusListener(_onMotionPreviewSequenceStatus);
    _tabController.addListener(_onOsgEditorTabChanged);
  }

  void _onOsgEditorTabChanged() {
    final int i = _tabController.index;
    if (i == _lastTabIndexForMotion) {
      return;
    }
    _lastTabIndexForMotion = i;
    if (_motionPreviewSequence.isAnimating || _motionPreviewActive) {
      _motionPreviewSequence.stop();
      _motionPreviewSequence.value = 0;
      if (_motionPreviewActive) {
        setState(() {
          _motionPreviewActive = false;
        });
      }
    }
  }

  void _onMotionPreviewSequenceStatus(AnimationStatus status) {
    if (!mounted) {
      return;
    }
    if (status == AnimationStatus.completed) {
      if (_motionPreviewLoop) {
        _motionPreviewSequence.forward(from: 0);
      } else {
        setState(() {
          _motionPreviewActive = false;
        });
        // Defer reset: setting value inside a status callback re-enters
        // notifyListeners/status while the controller is still notifying.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            return;
          }
          if (!_motionPreviewActive && !_motionPreviewSequence.isAnimating) {
            _motionPreviewSequence.value = 0;
          }
        });
      }
    }
  }

  OsgMotionPreviewSample? _motionPreviewSampleForTab(int tabIndex) {
    if (!_motionPreviewActive || _tabController.index != tabIndex) {
      return null;
    }
    final OsgPreset p = _draftOsg.workspacePresets[tabIndex];
    final int exitMs = OsgPreset.clampVisibilityDurationMs(
      p.visibilityExitDurationMs,
    );
    final int enterMs = OsgPreset.clampVisibilityDurationMs(
      p.visibilityEnterDurationMs,
    );
    final double v = _motionPreviewSequence.value;
    final double totalMs =
        (exitMs + _motionPreviewBetweenMs + enterMs).toDouble();
    final double exitEnd = exitMs / totalMs;
    final double gapEnd = (exitMs + _motionPreviewBetweenMs) / totalMs;
    if (v < exitEnd) {
      final double t = exitEnd <= 1e-9 ? 1.0 : (v / exitEnd).clamp(0.0, 1.0);
      final double shown = 1.0 - t;
      return OsgMotionPreviewSample(shown: shown, isEnterLeg: false);
    }
    if (v < gapEnd) {
      return const OsgMotionPreviewSample(shown: 0.0, isEnterLeg: false);
    }
    final double enterSpan = (1.0 - gapEnd).clamp(1e-9, 1.0);
    final double t = ((v - gapEnd) / enterSpan).clamp(0.0, 1.0);
    return OsgMotionPreviewSample(shown: t, isEnterLeg: true);
  }

  void _startOsgMotionPreview({
    required int presetIndex,
    required bool loop,
  }) {
    final OsgPreset p = _draftOsg.workspacePresets[presetIndex];
    final int exitMs = OsgPreset.clampVisibilityDurationMs(
      p.visibilityExitDurationMs,
    );
    final int enterMs = OsgPreset.clampVisibilityDurationMs(
      p.visibilityEnterDurationMs,
    );
    _motionPreviewSequence.duration = Duration(
      milliseconds: exitMs + _motionPreviewBetweenMs + enterMs,
    );
    setState(() {
      _motionPreviewLoop = loop;
      _motionPreviewActive = true;
    });
    _motionPreviewSequence.forward(from: 0);
  }

  Future<void> _loadSystemFontNames() async {
    await Future<void>.delayed(Duration.zero);
    if (!mounted) {
      return;
    }
    try {
      final List<String> names = List<String>.from(SystemFonts().getFontList());
      names.sort(
        (String a, String b) => a.toLowerCase().compareTo(b.toLowerCase()),
      );
      if (mounted) {
        setState(() {
          _systemFontNames = names;
          _systemFontsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _systemFontNames = <String>[];
          _systemFontsLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onOsgEditorTabChanged);
    _tabController.dispose();
    _motionPreviewSequence.removeStatusListener(_onMotionPreviewSequenceStatus);
    _motionPreviewSequence.dispose();
    _semanticTypesScrollController.dispose();
    super.dispose();
  }

  Future<void> _persistOsg(DashboardViewModel vm) async {
    await vm.saveOsgWorkspaceConfig(_draftOsg);
  }

  Future<void> _importTemplate(int presetIndex) async {
    final FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result == null || result.files.single.path == null) {
      return;
    }
    final String srcPath = result.files.single.path!;
    final String base = p.basename(srcPath);
    final String destDir = p.join(widget.workspaceRoot, "osg");
    await Directory(destDir).create(recursive: true);
    final String destPath = p.join(destDir, "preset_${presetIndex}_$base");
    await File(srcPath).copy(destPath);
    final String relative = WorkspaceMediaPaths.normalizeStored(
      p.join("osg", "preset_${presetIndex}_$base").replaceAll("\\", "/"),
    );
    final double? asp = await osgReadTemplatePixelAspect(File(destPath));
    if (!mounted) {
      return;
    }
    final DashboardViewModel vm = context.read<DashboardViewModel>();
    final double playoutAspect = vm.playoutOutputSize.aspectRatio;
    final double imgAsp = asp ?? 16 / 9;
    setState(() {
      final List<OsgPreset> list = _draftOsg.workspacePresets.toList();
      final OsgPreset old = list[presetIndex];
      final OsgNormRect frame = osgClampFrameWithImageAspect(
        frame: old.frame,
        imageWidthOverHeight: imgAsp,
        playoutAspect: playoutAspect,
      );
      list[presetIndex] = old.copyWith(
        templateRelativePath: relative,
        frame: frame,
        templatePixelAspect: asp,
        templateBackgroundKind: OsgTemplateBackgroundKind.image,
        templateSolidWidthPx: 0,
        templateSolidHeightPx: 0,
      );
      _draftOsg = OsgWorkspaceConfig(presets: list);
    });
  }

  OsgNormRect _frameLockedToTemplateAspect(
    OsgPreset preset,
    OsgNormRect raw,
    PlayoutOutputSize po,
  ) {
    final double asp = preset.templateAspectRatioForFrame;
    return osgClampFrameWithImageAspect(
      frame: raw,
      imageWidthOverHeight: asp,
      playoutAspect: po.aspectRatio,
    );
  }

  void _replacePreset(int index, OsgPreset next) {
    setState(() {
      final List<OsgPreset> list = _draftOsg.workspacePresets.toList();
      list[index] = next;
      _draftOsg = OsgWorkspaceConfig(presets: list);
    });
  }

  Future<int?> _promptCopyPresetSource(
    BuildContext context,
    int excludeIndex,
  ) {
    return showDialog<int>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text("Copy Settings From"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (int i = 0; i < 5; i++)
                  if (i != excludeIndex)
                    ListTile(
                      title: Text(
                        "Preset ${OsgPresetSlot.values[i].playoutHotkeyDigitLabel}",
                      ),
                      onTap: () => Navigator.pop(ctx, i),
                    ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _copyPresetFromAnother(
    BuildContext context,
    int targetIndex,
  ) async {
    final int? source = await _promptCopyPresetSource(context, targetIndex);
    if (!context.mounted || source == null) {
      return;
    }
    final OsgPreset src = _draftOsg.workspacePresets[source];
    final OsgPreset clone = OsgPreset.fromJson(
      Map<String, Object?>.from(src.toJson()),
    );
    _replacePreset(targetIndex, clone);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Copied settings from preset "
            "${OsgPresetSlot.values[source].playoutHotkeyDigitLabel}.",
          ),
        ),
      );
    }
  }

  Future<void> _exportOsgPresetPack(BuildContext context) async {
    final Uint8List bytes = buildOsgPresetPackZip(
      workspaceRoot: widget.workspaceRoot,
      config: _draftOsg,
    );
    final String stamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      RegExp(r"[:.-]"),
      "",
    );
    final String? path = await FilePicker.saveFile(
      dialogTitle: "Export OSG presets",
      fileName: "osg_presets_$stamp.zip",
      type: FileType.custom,
      allowedExtensions: const <String>["zip"],
    );
    if (!context.mounted || path == null) {
      return;
    }
    try {
      await File(path).writeAsBytes(bytes, flush: true);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Exported to $path")),
        );
      }
    } on Object catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Export failed: $e")),
        );
      }
    }
  }

  Future<void> _importOsgPresetPack(BuildContext context) async {
    final FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>["zip"],
      withData: true,
    );
    if (!context.mounted || result == null || result.files.isEmpty) {
      return;
    }
    final PlatformFile f = result.files.single;
    Uint8List? bytes = f.bytes;
    if (bytes == null && f.path != null) {
      try {
        bytes = await File(f.path!).readAsBytes();
      } on Object catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Could not read file: $e")),
          );
        }
        return;
      }
    }
    if (bytes == null || bytes.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Empty or unreadable ZIP.")),
        );
      }
      return;
    }
    final OsgPresetPackImportResult r = await importOsgPresetPackFromZipBytes(
      workspaceRoot: widget.workspaceRoot,
      zipBytes: bytes,
    );
    if (!context.mounted) {
      return;
    }
    if (!r.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            r.warnings.isEmpty ? "Import failed." : r.warnings.join(" "),
          ),
        ),
      );
      return;
    }
    setState(() {
      _draftOsg = r.config;
    });
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          r.warnings.isEmpty
              ? "Imported OSG presets from ZIP."
              : "Imported OSG presets (${r.warnings.length} warning(s)).",
        ),
      ),
    );
    if (r.warnings.isNotEmpty && context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          title: const Text("Import Warnings"),
          content: SingleChildScrollView(
            child: Text(r.warnings.join("\n")),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Close"),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final DashboardViewModel vm = context.watch<DashboardViewModel>();
    return Scaffold(
      appBar: AppBar(
        title: const Text("On-screen graphics"),
        actions: <Widget>[
          IconButton(
            tooltip: "Export OSG presets (ZIP)",
            icon: const Icon(Icons.folder_zip_outlined),
            onPressed: () => unawaited(_exportOsgPresetPack(context)),
          ),
          IconButton(
            tooltip: "Import OSG presets (ZIP)",
            icon: const Icon(Icons.unarchive_outlined),
            onPressed: () => unawaited(_importOsgPresetPack(context)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Done"),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  flex: 1,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      scaleDimension(context, 16),
                      scaleDimension(context, 8),
                      scaleDimension(context, 16),
                      scaleDimension(context, 4),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          "Playout canvas: ${vm.playoutOutputSize.width}×${vm.playoutOutputSize.height} px "
                          "(Workspace Settings).",
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          "Semantic types",
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Expanded(
                          child: Scrollbar(
                            controller: _semanticTypesScrollController,
                            child: ListView(
                              controller: _semanticTypesScrollController,
                              padding: EdgeInsets.zero,
                              children: vm.tagSemanticTypes
                                  .map(
                                    (TagSemanticType t) =>
                                        _semanticTypeTile(context, vm, t),
                                  )
                                  .toList(),
                            ),
                          ),
                        ),
                        FilledButton.tonal(
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () async {
                            final String? name = await _promptName(
                              context,
                              "New type",
                            );
                            if (name == null || name.isEmpty) {
                              return;
                            }
                            await vm.insertTagSemanticType(name: name);
                          },
                          child: const Text("Add type"),
                        ),
                      ],
                    ),
                  ),
                ),
                Material(
                  color: Theme.of(context).colorScheme.surface,
                  child: TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    tabs: <Widget>[
                      for (final OsgPresetSlot s in OsgPresetSlot.values)
                        Tab(text: "Preset ${s.playoutHotkeyDigitLabel}"),
                    ],
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: TabBarView(
                    controller: _tabController,
                    children: <Widget>[
                      for (int i = 0; i < 5; i++)
                        _presetTab(context, vm, i),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            minimum: EdgeInsets.fromLTRB(
              scaleDimension(context, 16),
              scaleDimension(context, 8),
              scaleDimension(context, 16),
              scaleDimension(context, 16),
            ),
            child: FilledButton.icon(
              onPressed: () async {
                await _persistOsg(vm);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("OSG configuration saved.")),
                  );
                }
              },
              icon: const Icon(Icons.save),
              label: const Text("Save all OSG settings"),
            ),
          ),
        ],
      ),
    );
  }

  Widget _semanticTypeTile(
    BuildContext context,
    DashboardViewModel vm,
    TagSemanticType t,
  ) {
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(vertical: 2),
      minLeadingWidth: 28,
      leading: t.iconCodePoint != null
          ? Icon(osgMaterialIconFromCodePoint(t.iconCodePoint!), size: 22)
          : Icon(Icons.label_outline, size: 22, color: Colors.grey.shade600),
      title: Text(t.name, style: Theme.of(context).textTheme.bodyMedium),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            padding: EdgeInsets.zero,
            tooltip: "Choose icon",
            icon: const Icon(Icons.emoji_emotions_outlined, size: 20),
            onPressed: () async {
              final Object? r = await showOsgSemanticTypeIconPicker(context);
              if (!context.mounted) {
                return;
              }
              if (r == null) {
                return;
              }
              if (r is OsgSemanticIconClear) {
                await vm.updateTagSemanticType(
                  id: t.id,
                  name: t.name,
                  iconCodePoint: null,
                );
              } else if (r is IconData) {
                await vm.updateTagSemanticType(
                  id: t.id,
                  name: t.name,
                  iconCodePoint: r.codePoint,
                );
              }
            },
          ),
          IconButton(
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            padding: EdgeInsets.zero,
            tooltip: "Delete type",
            icon: const Icon(Icons.delete_outline, size: 20),
            onPressed: () async {
              final bool ok = await vm.deleteTagSemanticType(t.id);
              if (context.mounted && !ok) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Cannot delete: type is still in use."),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _presetTab(BuildContext context, DashboardViewModel vm, int index) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        scaleDimension(context, 16),
        scaleDimension(context, 12),
        scaleDimension(context, 16),
        scaleDimension(context, 24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            "Previews",
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text(
            "Left: template only. "
            "Right: template in screen space.",
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 400,
            width: double.infinity,
            child: Builder(
              builder: (BuildContext context) {
                final Map<int, String> semanticPreviewNames = <int, String>{
                  for (final TagSemanticType t in vm.tagSemanticTypes)
                    t.id: t.name,
                };
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(
                      child: OsgPresetCanvasPreview(
                        playoutOutputSize: vm.playoutOutputSize,
                        workspaceRoot: widget.workspaceRoot,
                        preset: _draftOsg.workspacePresets[index],
                        interaction: OsgEditorPreviewInteraction.slots,
                        graphicLocalLayout: true,
                        dimOutsideFrame: false,
                        applyLayerOpacity: false,
                        semanticTypeNamesById: semanticPreviewNames,
                        onSlotChanged: (int slotIndex, OsgSlot slot) {
                          final OsgPreset p = _draftOsg.workspacePresets[index];
                          final List<OsgSlot> slots =
                              List<OsgSlot>.from(p.slots);
                          slots[slotIndex] = slot;
                          _replacePreset(index, p.copyWith(slots: slots));
                        },
                      ),
                    ),
                    SizedBox(width: scaleDimension(context, 10)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Text(
                                "Preview Motion",
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              const Spacer(),
                              TextButton(
                                onPressed: () {
                                  _motionPreviewSequence.stop();
                                  _motionPreviewSequence.value = 0;
                                  _startOsgMotionPreview(
                                    presetIndex: index,
                                    loop: _motionPreviewLoop,
                                  );
                                },
                                child: const Text("Play"),
                              ),
                              FilterChip(
                                label: const Text("Loop"),
                                selected: _motionPreviewLoop,
                                onSelected: (bool v) {
                                  setState(() {
                                    _motionPreviewLoop = v;
                                  });
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Expanded(
                            child: AnimatedBuilder(
                              animation: _motionPreviewSequence,
                              builder: (BuildContext context, Widget? child) {
                                return OsgPresetCanvasPreview(
                                  playoutOutputSize: vm.playoutOutputSize,
                                  workspaceRoot: widget.workspaceRoot,
                                  preset: _draftOsg.workspacePresets[index],
                                  interaction:
                                      OsgEditorPreviewInteraction.frame,
                                  graphicLocalLayout: false,
                                  dimOutsideFrame: false,
                                  applyLayerOpacity: true,
                                  semanticTypeNamesById: semanticPreviewNames,
                                  motionPreviewSample:
                                      _motionPreviewSampleForTab(index),
                                  onFrameChanged: (OsgNormRect next) {
                                    final OsgPreset p =
                                        _draftOsg.workspacePresets[index];
                                    _replacePreset(
                                      index,
                                      p.copyWith(frame: next),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          _presetControls(context, vm, index),
        ],
      ),
    );
  }

  Widget _presetControls(
    BuildContext context,
    DashboardViewModel vm,
    int index,
  ) {
    final OsgPreset preset = _draftOsg.workspacePresets[index];
    final String hotkeyLabel =
        OsgPresetSlot.values[index].playoutHotkeyDigitLabel;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(
                  "Preset $hotkeyLabel",
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Spacer(),
                Switch(
                  value: preset.enabled,
                  onChanged: (bool v) {
                    _replacePreset(index, preset.copyWith(enabled: v));
                  },
                ),
              ],
            ),
            Text(
              preset.templateBackgroundKind == OsgTemplateBackgroundKind.solid
                  ? "Solid color (${preset.templateSolidWidthPx}×${preset.templateSolidHeightPx} px, aspect ${preset.templateAspectRatioForFrame.toStringAsFixed(3)} W÷H)."
                  : (preset.templateRelativePath.isEmpty
                        ? "No template image"
                        : preset.templateRelativePath),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                SegmentedButton<OsgTemplateBackgroundKind>(
                  segments: const <ButtonSegment<OsgTemplateBackgroundKind>>[
                    ButtonSegment<OsgTemplateBackgroundKind>(
                      value: OsgTemplateBackgroundKind.image,
                      label: Text("Image"),
                      icon: Icon(Icons.image_outlined, size: 18),
                    ),
                    ButtonSegment<OsgTemplateBackgroundKind>(
                      value: OsgTemplateBackgroundKind.solid,
                      label: Text("Color"),
                      icon: Icon(Icons.format_color_fill, size: 18),
                    ),
                  ],
                  selected: <OsgTemplateBackgroundKind>{
                    preset.templateBackgroundKind,
                  },
                  onSelectionChanged: (Set<OsgTemplateBackgroundKind> next) {
                    if (next.isEmpty) {
                      return;
                    }
                    final OsgTemplateBackgroundKind k = next.single;
                    if (k == OsgTemplateBackgroundKind.image) {
                      _replacePreset(
                        index,
                        preset.copyWith(
                          templateBackgroundKind: k,
                          templateSolidWidthPx: 0,
                          templateSolidHeightPx: 0,
                        ),
                      );
                      return;
                    }
                    int w = preset.templateSolidWidthPx;
                    int h = preset.templateSolidHeightPx;
                    if (w <= 0 || h <= 0) {
                      final double? a = preset.templatePixelAspect;
                      if (a != null && a > 1e-9) {
                        h = 720;
                        w = (a * h).round().clamp(8, 999999);
                      } else {
                        final (int fw, int fh) = osgSolidTemplatePixelsForFrame(
                          preset.frame,
                          vm.playoutOutputSize,
                        );
                        w = fw;
                        h = fh;
                      }
                    }
                    _replacePreset(
                      index,
                      preset.copyWith(
                        templateBackgroundKind: k,
                        templateSolidWidthPx: w,
                        templateSolidHeightPx: h,
                        templatePixelAspect: w / h,
                      ),
                    );
                  },
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => unawaited(
                    _copyPresetFromAnother(context, index),
                  ),
                  child: const Text("Copy From…"),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                if (preset.templateBackgroundKind ==
                    OsgTemplateBackgroundKind.image)
                  OutlinedButton.icon(
                    onPressed: () => unawaited(_importTemplate(index)),
                    icon: const Icon(Icons.image_outlined),
                    label: const Text("Import image"),
                  ),
                if (preset.templateBackgroundKind ==
                    OsgTemplateBackgroundKind.solid)
                  RgbaColorPickerButton(
                    label: "Background",
                    valueArgb: preset.templateSolidArgb,
                    onChanged: (int v) => _replacePreset(
                      index,
                      preset.copyWith(templateSolidArgb: v),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: () {
                    final List<OsgSlot> slots = List<OsgSlot>.from(preset.slots)
                      ..add(
                        const OsgSlot(
                          textSource: OsgTextSource.fixed,
                          fixedText: "Text",
                          box: OsgNormRect(
                            x: 0.05,
                            y: 0.85,
                            width: 0.5,
                            height: 0.08,
                          ),
                          textColorArgb: 0xFFFFFFFF,
                        ),
                      );
                    _replacePreset(
                      index,
                      preset.copyWith(slots: slots),
                    );
                  },
                  icon: const Icon(Icons.add),
                  label: const Text("Add text slot"),
                ),
              ],
            ),
            if (preset.templateBackgroundKind ==
                OsgTemplateBackgroundKind.solid) ...<Widget>[
              SizedBox(height: scaleDimension(context, 8)),
              _SolidGraphicSizeFields(
                key: ValueKey<int>(index),
                widthPx: preset.templateSolidWidthPx,
                heightPx: preset.templateSolidHeightPx,
                onCommit: (int w, int h) {
                  final double asp = w / h;
                  final OsgNormRect frame = osgClampFrameWithImageAspect(
                    frame: preset.frame,
                    imageWidthOverHeight: asp,
                    playoutAspect: vm.playoutOutputSize.aspectRatio,
                  );
                  _replacePreset(
                    index,
                    preset.copyWith(
                      templateSolidWidthPx: w,
                      templateSolidHeightPx: h,
                      templatePixelAspect: asp,
                      frame: frame,
                    ),
                  );
                },
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Text(
                  "Layer opacity",
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                Expanded(
                  child: Slider(
                    value: preset.layerOpacity.clamp(0.0, 1.0),
                    min: 0,
                    max: 1,
                    divisions: 20,
                    label: "${(preset.layerOpacity * 100).round()}%",
                    onChanged: (double v) => _replacePreset(
                      index,
                      preset.copyWith(layerOpacity: v),
                    ),
                  ),
                ),
              ],
            ),
            Row(
              children: <Widget>[
                Text(
                  "Corner radius",
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                Expanded(
                  child: Slider(
                    value: preset.templateCornerRadiusNorm.clamp(0.0, 0.25),
                    min: 0,
                    max: 0.25,
                    divisions: 25,
                    label:
                        "${(preset.templateCornerRadiusNorm * 100).toStringAsFixed(0)}% min edge",
                    onChanged: (double v) => _replacePreset(
                      index,
                      preset.copyWith(templateCornerRadiusNorm: v),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              "Show / Hide Motion",
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 4),
            Text(
              "Slide distance is percent of the overlay frame along the chosen axis "
              "(above 100% travels farther than one frame width or height). "
              "Enter/Exit Duration is the full transition (80–4000 ms). "
              "When a slide is selected, Fade Duration may be shorter so the fade "
              "finishes while motion continues. "
              "Preview motion assumes the overlay is on screen: it plays exit, pauses, then enter.",
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      InputDecorator(
                        decoration: _osgEditorDenseBorderlessDecoration(
                          labelText: "Enter",
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<OsgPresetVisibilityMotion>(
                            isExpanded: true,
                            value: preset.visibilityEnterMotion,
                            items: <DropdownMenuItem<OsgPresetVisibilityMotion>>[
                              for (final OsgPresetVisibilityMotion m
                                  in OsgPresetVisibilityMotion.values)
                                DropdownMenuItem<OsgPresetVisibilityMotion>(
                                  value: m,
                                  child: Text(
                                    _osgVisibilityMotionMenuLabel(
                                      m,
                                      forExit: false,
                                    ),
                                  ),
                                ),
                            ],
                            onChanged: (OsgPresetVisibilityMotion? m) {
                              if (m == null) {
                                return;
                              }
                              _replacePreset(
                                index,
                                preset.copyWith(visibilityEnterMotion: m),
                              );
                            },
                          ),
                        ),
                      ),
                      if (preset.visibilityEnterMotion !=
                          OsgPresetVisibilityMotion.none) ...<Widget>[
                        const SizedBox(height: 6),
                        Text(
                          "Enter Slide",
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        Slider(
                          value:
                              (preset.visibilityEnterSlideDistanceNorm * 100)
                                  .clamp(5.0, 250.0),
                          min: 5,
                          max: 250,
                          divisions: 49,
                          label:
                              "${(preset.visibilityEnterSlideDistanceNorm * 100).round()}%",
                          onChanged: (double v) => _replacePreset(
                            index,
                            preset.copyWith(
                              visibilityEnterSlideDistanceNorm: v / 100.0,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        "Enter Duration",
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      Slider(
                        value: OsgPreset.clampVisibilityDurationMs(
                          preset.visibilityEnterDurationMs,
                        ).toDouble(),
                        min: 80,
                        max: 4000,
                        divisions: 49,
                        label:
                            "${OsgPreset.clampVisibilityDurationMs(preset.visibilityEnterDurationMs)} ms",
                        onChanged: (double v) => _replacePreset(
                          index,
                          preset.copyWith(
                            visibilityEnterDurationMs: v.round(),
                          ),
                        ),
                      ),
                      if (preset.visibilityEnterMotion !=
                          OsgPresetVisibilityMotion.none) ...<Widget>[
                        const SizedBox(height: 6),
                        Text(
                          "Enter Fade Duration",
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        Builder(
                          builder: (BuildContext context) {
                            final int enterDur =
                                OsgPreset.clampVisibilityDurationMs(
                              preset.visibilityEnterDurationMs,
                            );
                            final int enterFade =
                                OsgPreset.effectiveVisibilityFadeDurationMs(
                              fadeMs: preset.visibilityEnterFadeDurationMs,
                              transitionMs: enterDur,
                              motion: preset.visibilityEnterMotion,
                            );
                            return Slider(
                              value: enterFade.toDouble(),
                              min: 80,
                              max: enterDur.toDouble(),
                              divisions: enterDur <= 80
                                  ? 1
                                  : ((enterDur - 80) / 80).round().clamp(1, 49),
                              label: "$enterFade ms",
                              onChanged: (double v) => _replacePreset(
                                index,
                                preset.copyWith(
                                  visibilityEnterFadeDurationMs: v.round(),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(width: scaleDimension(context, 12)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      InputDecorator(
                        decoration: _osgEditorDenseBorderlessDecoration(
                          labelText: "Exit",
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<OsgPresetVisibilityMotion>(
                            isExpanded: true,
                            value: preset.visibilityExitMotion,
                            items: <DropdownMenuItem<OsgPresetVisibilityMotion>>[
                              for (final OsgPresetVisibilityMotion m
                                  in OsgPresetVisibilityMotion.values)
                                DropdownMenuItem<OsgPresetVisibilityMotion>(
                                  value: m,
                                  child: Text(
                                    _osgVisibilityMotionMenuLabel(
                                      m,
                                      forExit: true,
                                    ),
                                  ),
                                ),
                            ],
                            onChanged: (OsgPresetVisibilityMotion? m) {
                              if (m == null) {
                                return;
                              }
                              _replacePreset(
                                index,
                                preset.copyWith(visibilityExitMotion: m),
                              );
                            },
                          ),
                        ),
                      ),
                      if (preset.visibilityExitMotion !=
                          OsgPresetVisibilityMotion.none) ...<Widget>[
                        const SizedBox(height: 6),
                        Text(
                          "Exit Slide",
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        Slider(
                          value:
                              (preset.visibilityExitSlideDistanceNorm * 100)
                                  .clamp(5.0, 250.0),
                          min: 5,
                          max: 250,
                          divisions: 49,
                          label:
                              "${(preset.visibilityExitSlideDistanceNorm * 100).round()}%",
                          onChanged: (double v) => _replacePreset(
                            index,
                            preset.copyWith(
                              visibilityExitSlideDistanceNorm: v / 100.0,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        "Exit Duration",
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      Slider(
                        value: OsgPreset.clampVisibilityDurationMs(
                          preset.visibilityExitDurationMs,
                        ).toDouble(),
                        min: 80,
                        max: 4000,
                        divisions: 49,
                        label:
                            "${OsgPreset.clampVisibilityDurationMs(preset.visibilityExitDurationMs)} ms",
                        onChanged: (double v) => _replacePreset(
                          index,
                          preset.copyWith(
                            visibilityExitDurationMs: v.round(),
                          ),
                        ),
                      ),
                      if (preset.visibilityExitMotion !=
                          OsgPresetVisibilityMotion.none) ...<Widget>[
                        const SizedBox(height: 6),
                        Text(
                          "Exit Fade Duration",
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        Builder(
                          builder: (BuildContext context) {
                            final int exitDur =
                                OsgPreset.clampVisibilityDurationMs(
                              preset.visibilityExitDurationMs,
                            );
                            final int exitFade =
                                OsgPreset.effectiveVisibilityFadeDurationMs(
                              fadeMs: preset.visibilityExitFadeDurationMs,
                              transitionMs: exitDur,
                              motion: preset.visibilityExitMotion,
                            );
                            return Slider(
                              value: exitFade.toDouble(),
                              min: 80,
                              max: exitDur.toDouble(),
                              divisions: exitDur <= 80
                                  ? 1
                                  : ((exitDur - 80) / 80).round().clamp(1, 49),
                              label: "$exitFade ms",
                              onChanged: (double v) => _replacePreset(
                                index,
                                preset.copyWith(
                                  visibilityExitFadeDurationMs: v.round(),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              "Required Semantic Tags",
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 4),
            Text(
              "The overlay stays off until the media row has at least one tag for each selected type.",
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (vm.tagSemanticTypes.isEmpty)
              Text(
                "None Configured — Add Types In Workspace Settings.",
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final TagSemanticType t in vm.tagSemanticTypes)
                    FilterChip(
                      label: Text(t.name),
                      selected: preset.requiredSemanticTypeIds.contains(t.id),
                      onSelected: (bool v) {
                        final Set<int> next =
                            preset.requiredSemanticTypeIds.toSet();
                        if (v) {
                          next.add(t.id);
                        } else {
                          next.remove(t.id);
                        }
                        final List<int> sorted = next.toList()..sort();
                        _replacePreset(
                          index,
                          preset.copyWith(
                            requiredSemanticTypeIds: sorted,
                          ),
                        );
                      },
                    ),
                ],
              ),
            const SizedBox(height: 12),
            _frameEditor(context, vm, index, preset),
            const SizedBox(height: 8),
            ...preset.slots.asMap().entries.map(
              (MapEntry<int, OsgSlot> e) => _OsgSlotRow(
                key: ValueKey<String>("slot_${index}_${e.key}"),
                presetIndex: index,
                slotIndex: e.key,
                slot: e.value,
                preset: preset,
                vm: vm,
                systemFontNames: _systemFontNames,
                systemFontsLoading: _systemFontsLoading,
                onSlotChanged: (OsgSlot next) => _updateSlot(index, e.key, next),
                onDelete: () {
                  final List<OsgSlot> slots = List<OsgSlot>.from(preset.slots)
                    ..removeAt(e.key);
                  _replacePreset(index, preset.copyWith(slots: slots));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _frameEditor(
    BuildContext context,
    DashboardViewModel vm,
    int presetIndex,
    OsgPreset preset,
  ) {
    final PlayoutOutputSize po = vm.playoutOutputSize;
    return OsgScaledCanvasRectFields(
      displayMode: OsgRectFieldDisplayMode.canvasPixels,
      canvasWidth: po.width,
      canvasHeight: po.height,
      normRect: preset.frame,
      label: "Frame (canvas pixels)",
      isSlotInFrame: false,
      frame: null,
      onNormChanged: (OsgNormRect next) {
        final OsgNormRect locked = _frameLockedToTemplateAspect(
          preset,
          next,
          po,
        );
        _replacePreset(
          presetIndex,
          preset.copyWith(frame: locked),
        );
      },
    );
  }

  void _updateSlot(int presetIndex, int slotIndex, OsgSlot nextSlot) {
    final OsgPreset preset = _draftOsg.workspacePresets[presetIndex];
    final List<OsgSlot> slots = List<OsgSlot>.from(preset.slots);
    slots[slotIndex] = nextSlot;
    _replacePreset(presetIndex, preset.copyWith(slots: slots));
  }
}

class _OsgSlotRow extends StatefulWidget {
  const _OsgSlotRow({
    super.key,
    required this.presetIndex,
    required this.slotIndex,
    required this.slot,
    required this.preset,
    required this.vm,
    required this.systemFontNames,
    required this.systemFontsLoading,
    required this.onSlotChanged,
    required this.onDelete,
  });

  final int presetIndex;
  final int slotIndex;
  final OsgSlot slot;
  final OsgPreset preset;
  final DashboardViewModel vm;
  final List<String> systemFontNames;
  final bool systemFontsLoading;
  final ValueChanged<OsgSlot> onSlotChanged;
  final VoidCallback onDelete;

  @override
  State<_OsgSlotRow> createState() => _OsgSlotRowState();
}

class _OsgSlotRowState extends State<_OsgSlotRow> {
  late final TextEditingController _fontSizePct;
  final FocusNode _fontSizeFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _fontSizePct = TextEditingController(text: _fontSizePctLabel(widget.slot.fontSizeNorm));
  }

  static String _fontSizePctLabel(double fontSizeNorm) {
    return (fontSizeNorm * 100).toStringAsFixed(1);
  }

  @override
  void didUpdateWidget(covariant _OsgSlotRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slot.fontSizeNorm != widget.slot.fontSizeNorm &&
        !_fontSizeFocus.hasFocus) {
      _fontSizePct.text = _fontSizePctLabel(widget.slot.fontSizeNorm);
    }
  }

  @override
  void dispose() {
    _fontSizePct.dispose();
    _fontSizeFocus.dispose();
    super.dispose();
  }

  void _emitFontSizePct() {
    final double? pct = double.tryParse(_fontSizePct.text.trim());
    if (pct == null) {
      return;
    }
    final double norm = (pct / 100).clamp(0.005, 0.25);
    widget.onSlotChanged(widget.slot.copyWith(fontSizeNorm: norm));
  }

  Future<void> _applyFontFamily(String? family) async {
    final String? trimmed = family?.trim();
    final String? nextFamily =
        trimmed == null || trimmed.isEmpty ? null : trimmed;
    if (nextFamily != null) {
      await SystemFonts().loadFont(nextFamily);
    }
    widget.onSlotChanged(widget.slot.copyWith(fontFamily: nextFamily));
  }

  @override
  Widget build(BuildContext context) {
    final OsgSlot slot = widget.slot;
    final OsgPreset preset = widget.preset;
    final DashboardViewModel vm = widget.vm;
    final double gap = scaleDimension(context, 8);
    final double sizeColW = scaleDimension(context, 56);
    final TextStyle? slotFieldLabelStyle =
        Theme.of(context).inputDecorationTheme.labelStyle ??
        Theme.of(context).textTheme.labelSmall;

    return Padding(
      padding: EdgeInsets.only(bottom: scaleDimension(context, 10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                "Slot ${widget.slotIndex + 1}",
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: widget.onDelete,
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<OsgTextSource>(
                  key: ValueKey<String>(
                    "src_${widget.presetIndex}_${widget.slotIndex}_${slot.textSource.name}",
                  ),
                  initialValue: slot.textSource,
                  isExpanded: true,
                  decoration: _osgEditorDenseBorderlessDecoration(
                    labelText: "Source",
                  ),
                  items: OsgTextSource.values
                      .map(
                        (OsgTextSource s) => DropdownMenuItem<OsgTextSource>(
                          value: s,
                          child: Text(s.label),
                        ),
                      )
                      .toList(),
                  onChanged: (OsgTextSource? v) {
                    if (v == null) {
                      return;
                    }
                    widget.onSlotChanged(slot.copyWith(textSource: v));
                  },
                ),
              ),
              SizedBox(width: gap),
              Expanded(
                flex: slot.textSource == OsgTextSource.fixed ? 4 : 2,
                child: switch (slot.textSource) {
                  OsgTextSource.fixed => TextFormField(
                      key: ValueKey<String>(
                        "fixed_${widget.presetIndex}_${widget.slotIndex}",
                      ),
                      initialValue: slot.fixedText,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      minLines: 2,
                      maxLines: 12,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: const InputDecoration(
                        labelText: "Fixed text",
                        alignLabelWithHint: true,
                        isDense: true,
                      ),
                      onChanged: (String v) =>
                          widget.onSlotChanged(slot.copyWith(fixedText: v)),
                    ),
                  OsgTextSource.semantic => vm.tagSemanticTypes.isEmpty
                      ? TextFormField(
                          key: ValueKey<String>(
                            "sem_empty_${widget.presetIndex}_${widget.slotIndex}",
                          ),
                          enabled: false,
                          initialValue: "—",
                          style: Theme.of(context).textTheme.bodySmall,
                          decoration: _osgEditorDenseBorderlessDecoration(
                            labelText: "Semantic type",
                            helperText: "Add semantic types above.",
                          ),
                        )
                      : DropdownButtonFormField<int>(
                          key: ValueKey<String>(
                            "sem_${widget.presetIndex}_${widget.slotIndex}_${slot.semanticTypeId}",
                          ),
                          isExpanded: true,
                          initialValue:
                              slot.semanticTypeId ?? vm.tagSemanticTypes.first.id,
                          decoration: _osgEditorDenseBorderlessDecoration(
                            labelText: "Semantic type",
                          ),
                          items: vm.tagSemanticTypes
                              .map(
                                (TagSemanticType t) => DropdownMenuItem<int>(
                                  value: t.id,
                                  child: Text(t.name),
                                ),
                              )
                              .toList(),
                          onChanged: (int? v) {
                            if (v != null) {
                              widget.onSlotChanged(
                                slot.copyWith(semanticTypeId: v),
                              );
                            }
                          },
                        ),
                  OsgTextSource.annotation => TextFormField(
                      key: ValueKey<String>(
                        "ann_${widget.presetIndex}_${widget.slotIndex}",
                      ),
                      enabled: false,
                      decoration: _osgEditorDenseBorderlessDecoration(
                        labelText: "Annotation",
                      ).copyWith(hintText: "Media item's annotation"),
                    ),
                },
              ),
              SizedBox(width: gap),
              Expanded(
                flex: 4,
                child: widget.systemFontsLoading
                    ? SizedBox(
                        height: scaleDimension(context, 40),
                        child: const Center(
                          child: LinearProgressIndicator(minHeight: 2),
                        ),
                      )
                    : widget.systemFontNames.isEmpty
                    ? TextFormField(
                        key: ValueKey<String>(
                          "fontmanual_${widget.presetIndex}_${widget.slotIndex}",
                        ),
                        initialValue: slot.fontFamily ?? "",
                        decoration: const InputDecoration(
                          labelText: "Font family",
                          isDense: true,
                        ),
                        onFieldSubmitted: (String v) => unawaited(_applyFontFamily(v)),
                      )
                    : AdaptiveAutocomplete<String>(
                        key: ValueKey<String>(
                          "fontac_${widget.presetIndex}_${widget.slotIndex}_${slot.fontFamily}",
                        ),
                        optionsBuilder: (TextEditingValue te) {
                          final String q = te.text.trim().toLowerCase();
                          if (q.isEmpty) {
                            return widget.systemFontNames.take(50);
                          }
                          return widget.systemFontNames
                              .where(
                                (String f) => f.toLowerCase().contains(q),
                              )
                              .take(50);
                        },
                        onSelected: (String f) => unawaited(_applyFontFamily(f)),
                        fieldViewBuilder: (
                          BuildContext context,
                          TextEditingController textEditingController,
                          FocusNode focusNode,
                          VoidCallback onFieldSubmitted,
                        ) {
                          if (!focusNode.hasFocus) {
                            final String? fam = widget.slot.fontFamily;
                            if (fam != null &&
                                fam.isNotEmpty &&
                                textEditingController.text != fam) {
                              textEditingController.text = fam;
                            }
                          }
                          return TextField(
                            controller: textEditingController,
                            focusNode: focusNode,
                            decoration: const InputDecoration(
                              labelText: "Font family",
                              isDense: true,
                            ),
                            onSubmitted: (String v) {
                              unawaited(_applyFontFamily(v));
                              onFieldSubmitted();
                            },
                          );
                        },
                      ),
              ),
              SizedBox(width: gap),
              SizedBox(
                width: sizeColW,
                child: TextField(
                  controller: _fontSizePct,
                  focusNode: _fontSizeFocus,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  maxLength: 6,
                  buildCounter: (
                    BuildContext c, {
                    required int currentLength,
                    required bool isFocused,
                    required int? maxLength,
                  }) =>
                      null,
                  decoration: const InputDecoration(
                    labelText: "% h",
                    isDense: true,
                  ),
                  onEditingComplete: _emitFontSizePct,
                  onSubmitted: (_) => _emitFontSizePct(),
                ),
              ),
              SizedBox(width: gap),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text("Align", style: slotFieldLabelStyle),
                  SizedBox(height: scaleDimension(context, 4)),
                  SegmentedButton<OsgSlotTextAlign>(
                    showSelectedIcon: false,
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    segments: const <ButtonSegment<OsgSlotTextAlign>>[
                      ButtonSegment<OsgSlotTextAlign>(
                        value: OsgSlotTextAlign.left,
                        label: Text("L"),
                        tooltip: "Left",
                      ),
                      ButtonSegment<OsgSlotTextAlign>(
                        value: OsgSlotTextAlign.center,
                        label: Text("C"),
                        tooltip: "Center",
                      ),
                      ButtonSegment<OsgSlotTextAlign>(
                        value: OsgSlotTextAlign.right,
                        label: Text("R"),
                        tooltip: "Right",
                      ),
                    ],
                    selected: <OsgSlotTextAlign>{slot.textAlign},
                    onSelectionChanged: (Set<OsgSlotTextAlign> next) {
                      if (next.isEmpty) {
                        return;
                      }
                      widget.onSlotChanged(
                        slot.copyWith(textAlign: next.single),
                      );
                    },
                  ),
                  SizedBox(height: scaleDimension(context, 6)),
                  SegmentedButton<OsgSlotVerticalAlign>(
                    showSelectedIcon: false,
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    segments: const <ButtonSegment<OsgSlotVerticalAlign>>[
                      ButtonSegment<OsgSlotVerticalAlign>(
                        value: OsgSlotVerticalAlign.top,
                        label: Text("T"),
                        tooltip: "Top",
                      ),
                      ButtonSegment<OsgSlotVerticalAlign>(
                        value: OsgSlotVerticalAlign.center,
                        label: Text("M"),
                        tooltip: "Middle",
                      ),
                      ButtonSegment<OsgSlotVerticalAlign>(
                        value: OsgSlotVerticalAlign.bottom,
                        label: Text("B"),
                        tooltip: "Bottom",
                      ),
                    ],
                    selected: <OsgSlotVerticalAlign>{slot.verticalAlign},
                    onSelectionChanged: (Set<OsgSlotVerticalAlign> next) {
                      if (next.isEmpty) {
                        return;
                      }
                      widget.onSlotChanged(
                        slot.copyWith(verticalAlign: next.single),
                      );
                    },
                  ),
                ],
              ),
              SizedBox(width: gap),
              RgbaColorPickerButton(
                label: "Text color",
                valueArgb: slot.textColorArgb,
                onChanged: (int v) =>
                    widget.onSlotChanged(slot.copyWith(textColorArgb: v)),
              ),
            ],
          ),
          SizedBox(height: gap),
          OsgScaledCanvasRectFields(
            displayMode: OsgRectFieldDisplayMode.graphicPercent,
            canvasWidth: widget.vm.playoutOutputSize.width,
            canvasHeight: widget.vm.playoutOutputSize.height,
            normRect: slot.box,
            label: "Slot box",
            isSlotInFrame: true,
            frame: preset.frame,
            onNormChanged: (OsgNormRect next) {
              widget.onSlotChanged(slot.copyWith(box: next));
            },
          ),
        ],
      ),
    );
  }
}

class _SolidGraphicSizeFields extends StatefulWidget {
  const _SolidGraphicSizeFields({
    super.key,
    required this.widthPx,
    required this.heightPx,
    required this.onCommit,
  });

  final int widthPx;
  final int heightPx;
  final void Function(int widthPx, int heightPx) onCommit;

  @override
  State<_SolidGraphicSizeFields> createState() =>
      _SolidGraphicSizeFieldsState();
}

class _SolidGraphicSizeFieldsState extends State<_SolidGraphicSizeFields> {
  late final TextEditingController _w;
  late final TextEditingController _h;
  final FocusNode _fW = FocusNode();
  final FocusNode _fH = FocusNode();

  @override
  void initState() {
    super.initState();
    _w = TextEditingController(text: "${widget.widthPx}");
    _h = TextEditingController(text: "${widget.heightPx}");
  }

  @override
  void didUpdateWidget(covariant _SolidGraphicSizeFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.widthPx != widget.widthPx && !_fW.hasFocus) {
      _w.text = "${widget.widthPx}";
    }
    if (oldWidget.heightPx != widget.heightPx && !_fH.hasFocus) {
      _h.text = "${widget.heightPx}";
    }
  }

  @override
  void dispose() {
    _w.dispose();
    _h.dispose();
    _fW.dispose();
    _fH.dispose();
    super.dispose();
  }

  void _commit() {
    final int w = int.tryParse(_w.text.trim()) ?? widget.widthPx;
    final int h = int.tryParse(_h.text.trim()) ?? widget.heightPx;
    widget.onCommit(w.clamp(8, 99999), h.clamp(8, 99999));
  }

  @override
  Widget build(BuildContext context) {
    final double fieldW = scaleDimension(context, 104);
    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: fieldW,
            child: TextField(
              controller: _w,
              focusNode: _fW,
              keyboardType: TextInputType.number,
              decoration: _osgEditorDenseBorderlessDecoration(
                labelText: "W px",
              ),
              onEditingComplete: _commit,
              onSubmitted: (_) => _commit(),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              scaleDimension(context, 8),
              scaleDimension(context, 20),
              scaleDimension(context, 8),
              0,
            ),
            child: const Text("×"),
          ),
          SizedBox(
            width: fieldW,
            child: TextField(
              controller: _h,
              focusNode: _fH,
              keyboardType: TextInputType.number,
              decoration: _osgEditorDenseBorderlessDecoration(
                labelText: "H px",
              ),
              onEditingComplete: _commit,
              onSubmitted: (_) => _commit(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Owns its own [TextEditingController] in a dedicated [StatefulWidget] so
/// disposal is tied to that widget leaving the tree (i.e. after the dialog's
/// exit transition finishes, including the framework's built-in Escape
/// dismissal) rather than to the caller's `await showDialog(...)` returning.
/// Disposing eagerly in a `finally` right after that await races the
/// still-animating dialog and throws "used after being disposed".
Future<String?> _promptName(BuildContext context, String title) {
  return showDialog<String>(
    context: context,
    builder: (BuildContext ctx) => _PromptNameDialog(title: title),
  );
}

class _PromptNameDialog extends StatefulWidget {
  const _PromptNameDialog({required this.title});

  final String title;

  @override
  State<_PromptNameDialog> createState() => _PromptNameDialogState();
}

class _PromptNameDialogState extends State<_PromptNameDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: "Name"),
        onSubmitted: (String value) =>
            Navigator.pop(context, value.trim()),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text("OK"),
        ),
      ],
    );
  }
}
