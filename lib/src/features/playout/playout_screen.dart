import "dart:async";

import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:provider/provider.dart";

import "package:obs_clipshow/src/app/ui_scale.dart";
import "package:obs_clipshow/src/features/dashboard/dashboard_view_model.dart";
import "package:obs_clipshow/src/features/playout/clip_player_view.dart";
import "package:obs_clipshow/src/features/playout/osg_playout_layer.dart";
import "package:obs_clipshow/src/features/playout/playout_clip.dart";
import "package:obs_clipshow/src/features/playout/playout_hotkeys_layer.dart";
import "package:obs_clipshow/src/features/playout/telestrator_canvas.dart";
import "package:obs_clipshow/src/features/playout/telestrator_model.dart";
import "package:obs_clipshow/src/osg/osg_models.dart";
import "package:obs_clipshow/src/workspace/workspace_settings.dart";
import "package:obs_clipshow/src/widgets/transient_hud_banner.dart";

bool _sameTelestratorDefaults(TelestratorDefaults a, TelestratorDefaults b) {
  return a.colorOneArgb == b.colorOneArgb &&
      a.colorTwoArgb == b.colorTwoArgb &&
      a.colorThreeArgb == b.colorThreeArgb &&
      a.brushSize == b.brushSize &&
      a.enabledByDefault == b.enabledByDefault;
}

class PlayoutScreen extends StatefulWidget {
  const PlayoutScreen({
    super.key,
    required this.clip,
    required this.osgWorkspaceConfig,
    required this.workspaceRoot,
    required this.tagSemanticTypes,
    required this.telestratorDefaults,
    required this.onResolveSemanticText,
    required this.onExitRequested,
    this.onFirstFrameReady,
  });

  final PlayoutClip clip;
  final OsgWorkspaceConfig osgWorkspaceConfig;
  final String workspaceRoot;
  final List<TagSemanticType> tagSemanticTypes;
  final TelestratorDefaults telestratorDefaults;
  final OsgSemanticResolve onResolveSemanticText;
  final Future<void> Function() onExitRequested;
  final VoidCallback? onFirstFrameReady;

  @override
  State<PlayoutScreen> createState() => _PlayoutScreenState();
}

class _PlayoutScreenState extends State<PlayoutScreen> {
  final Logger _logger = Logger("PlayoutScreen");
  final ClipPlayerController _playerController = ClipPlayerController();
  final TelestratorController _telestratorController = TelestratorController();
  bool _isExiting = false;
  bool _showEscapeHint = true;
  bool _showHelpOverlay = false;
  Timer? _hintTimer;
  OsgPresetVisibility _osgPresetVisible = const OsgPresetVisibility.allOff();
  int _osgRequirementFlashToken = 0;
  String _osgRequirementFlashText = "";

  bool _semanticIdSetsEqual(Set<int> a, Set<int> b) {
    if (a.length != b.length) {
      return false;
    }
    for (final int id in a) {
      if (!b.contains(id)) {
        return false;
      }
    }
    return true;
  }

  void _reconcileOsgVisibilityToRequirements({bool requestFrame = true}) {
    final Set<int> onMedia = widget.clip.semanticTypeIdsOnMedia;
    final List<OsgPreset> presets = widget.osgWorkspaceConfig.workspacePresets;
    OsgPresetVisibility next = _osgPresetVisible;
    bool changed = false;
    for (final OsgPresetSlot slot in OsgPresetSlot.values) {
      if (!next[slot]) {
        continue;
      }
      final OsgPreset p = presets[slot.presetIndex];
      if (!p.enabled) {
        next = next.withSlot(slot, false);
        changed = true;
        continue;
      }
      if (p.requiredSemanticTypeIds.isNotEmpty &&
          !p.semanticRequirementsSatisfiedBy(onMedia)) {
        next = next.withSlot(slot, false);
        changed = true;
      }
    }
    if (changed) {
      _osgPresetVisible = next;
      if (requestFrame && mounted) {
        setState(() {});
      }
    }
  }

  void _flashOsgRequirementMessage(String text) {
    setState(() {
      _osgRequirementFlashText = text;
      _osgRequirementFlashToken++;
    });
  }

  void _clearOsgRequirementFlash() {
    if (_osgRequirementFlashToken == 0) {
      return;
    }
    setState(() {
      _osgRequirementFlashToken = 0;
      _osgRequirementFlashText = "";
    });
  }

  void _toggleOsgPreset(OsgPresetSlot slot) {
    final int index = slot.presetIndex;
    if (index < 0 || index >= OsgPresetSlot.values.length) {
      return;
    }
    final OsgPreset preset = widget.osgWorkspaceConfig.workspacePresets[index];
    if (!preset.enabled) {
      return;
    }
    final bool next = !_osgPresetVisible[slot];
    if (next) {
      if (preset.requiredSemanticTypeIds.isNotEmpty) {
        final Set<int> onMedia = widget.clip.semanticTypeIdsOnMedia;
        if (!preset.semanticRequirementsSatisfiedBy(onMedia)) {
          _flashOsgRequirementMessage(
            osgMissingSemanticRequirementsMessage(
              preset: preset,
              semanticTypeIdsOnMedia: onMedia,
              tagSemanticTypes: widget.tagSemanticTypes,
            ),
          );
          return;
        }
      }
    }
    setState(() {
      _osgPresetVisible = _osgPresetVisible.withSlot(slot, next);
    });
  }

  @override
  void initState() {
    super.initState();
    final TelestratorDefaults d = widget.telestratorDefaults;
    _telestratorController.applyInitialTelestratorSettings(
      activeColor: d.colorOne,
      brushSize: d.brushSize,
      enabledByDefault: d.enabledByDefault,
    );
    final OsgPresetVisibility? initial = widget.clip.osgPresetVisibleInitial;
    if (initial != null) {
      _osgPresetVisible = initial;
    }
    _reconcileOsgVisibilityToRequirements(requestFrame: false);
    _hintTimer = Timer(const Duration(seconds: 1), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _showEscapeHint = false;
      });
    });
    _logger.info("Playout started for ${widget.clip.filePath}");
  }

  @override
  void didUpdateWidget(covariant PlayoutScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clip.mediaId != widget.clip.mediaId ||
        oldWidget.clip.mediaType != widget.clip.mediaType ||
        oldWidget.clip.semanticTagSnapshotVersion !=
            widget.clip.semanticTagSnapshotVersion ||
        !_semanticIdSetsEqual(
          oldWidget.clip.semanticTypeIdsOnMedia,
          widget.clip.semanticTypeIdsOnMedia,
        )) {
      _reconcileOsgVisibilityToRequirements();
    }
    if (!_sameTelestratorDefaults(
      oldWidget.telestratorDefaults,
      widget.telestratorDefaults,
    )) {
      final TelestratorDefaults d = widget.telestratorDefaults;
      _telestratorController.applyInitialTelestratorSettings(
        activeColor: d.colorOne,
        brushSize: d.brushSize,
        enabledByDefault: d.enabledByDefault,
      );
    }
  }

  Future<void> _requestExit() async {
    if (_isExiting) {
      return;
    }
    _isExiting = true;
    await widget.onExitRequested();
  }

  void _toggleHelpOverlay() {
    setState(() {
      _showHelpOverlay = !_showHelpOverlay;
    });
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _telestratorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double edgeInset = scaleDimension(context, 16);
    final DashboardViewModel viewModel = context.watch<DashboardViewModel>();
    return Scaffold(
      backgroundColor: Colors.black,
      body: PlayoutHotkeysLayer(
        controller: _playerController,
        onExitRequested: _requestExit,
        onHelpToggleRequested: _toggleHelpOverlay,
        onTelestratorToggleRequested: _telestratorController.toggleEnabled,
        onTelestratorClearRequested: _telestratorController.clear,
        onTelestratorUndoRequested: _telestratorController.undo,
        onSetTelestratorColor1Requested: () => _telestratorController.setColor(
          widget.telestratorDefaults.colorOne,
        ),
        onSetTelestratorColor2Requested: () => _telestratorController.setColor(
          widget.telestratorDefaults.colorTwo,
        ),
        onSetTelestratorColor3Requested: () => _telestratorController.setColor(
          widget.telestratorDefaults.colorThree,
        ),
        onDecreaseBrushRequested: _telestratorController.decreaseBrush,
        onIncreaseBrushRequested: _telestratorController.increaseBrush,
        onOsgPresetSlotToggle: _toggleOsgPreset,
        onVolumeUpRequested: () =>
            viewModel.nudgeClipVolume(PlaybackVolumeDefaults.step),
        onVolumeDownRequested: () =>
            viewModel.nudgeClipVolume(-PlaybackVolumeDefaults.step),
        onMuteToggleRequested: viewModel.toggleClipMute,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            ClipPlayerView(
              controller: _playerController,
              filePath: widget.clip.filePath,
              startTimeMs: widget.clip.startTimeMs,
              endTimeMs: widget.clip.endTimeMs,
              initialPositionMs: widget.clip.initialPositionMs,
              autoPlay: true,
              videoBoxFit: BoxFit.contain,
              volume: viewModel.effectiveClipVolume,
              onFirstFrameReady: widget.onFirstFrameReady,
            ),
            Positioned.fill(
              child: OsgPlayoutLayer(
                clip: widget.clip,
                config: widget.osgWorkspaceConfig,
                workspaceRoot: widget.workspaceRoot,
                resolveSemantic: widget.onResolveSemanticText,
                visible: _osgPresetVisible,
              ),
            ),
            Positioned.fill(
              child: TelestratorCanvas(
                controller: _telestratorController,
              ),
            ),
            Positioned(
              left: edgeInset,
              bottom: edgeInset,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (_osgRequirementFlashToken > 0)
                    Padding(
                      padding: EdgeInsets.only(bottom: scaleDimension(context, 8)),
                      child: TransientHudBanner(
                        key: ValueKey<int>(_osgRequirementFlashToken),
                        text: _osgRequirementFlashText,
                        onDismissed: _clearOsgRequirementFlash,
                      ),
                    ),
                  _TelestratorStatusHud(controller: _telestratorController),
                ],
              ),
            ),
            if (_showEscapeHint && !_showHelpOverlay)
              Positioned(
                right: edgeInset,
                bottom: edgeInset,
                child: const Text(
                  "Press Escape to return",
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            if (_showHelpOverlay) const _PlayoutHelpOverlay(),
          ],
        ),
      ),
    );
  }
}

class _TelestratorStatusHud extends StatefulWidget {
  const _TelestratorStatusHud({required this.controller});

  final TelestratorController controller;

  @override
  State<_TelestratorStatusHud> createState() => _TelestratorStatusHudState();
}

class _TelestratorStatusHudState extends State<_TelestratorStatusHud> {
  static const Duration _autoHideDelay = Duration(seconds: 1);
  static const Duration _fadeDuration = Duration(milliseconds: 220);

  Timer? _hideTimer;
  bool _isVisible = true;
  bool _lastEnabled = true;
  double _lastBrushSize = 0;
  Color _lastColor = const Color(0x00000000);

  @override
  void initState() {
    super.initState();
    _snapshotCurrentValues();
    widget.controller.addListener(_onControllerChanged);
    _restartHideTimer();
  }

  @override
  void didUpdateWidget(covariant _TelestratorStatusHud oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      _snapshotCurrentValues();
      widget.controller.addListener(_onControllerChanged);
      _showAndScheduleHide();
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _snapshotCurrentValues() {
    _lastEnabled = widget.controller.isEnabled;
    _lastBrushSize = widget.controller.brushSize;
    _lastColor = widget.controller.activeColor;
  }

  void _onControllerChanged() {
    final bool enabled = widget.controller.isEnabled;
    final double brushSize = widget.controller.brushSize;
    final Color color = widget.controller.activeColor;
    final bool statusChanged =
        enabled != _lastEnabled ||
        brushSize != _lastBrushSize ||
        color != _lastColor;
    _snapshotCurrentValues();
    if (!statusChanged) {
      return;
    }
    setState(() {
      _isVisible = true;
    });
    _restartHideTimer();
  }

  void _showAndScheduleHide() {
    if (!mounted) {
      return;
    }
    setState(() {
      _isVisible = true;
    });
    _restartHideTimer();
  }

  void _restartHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_autoHideDelay, () {
      if (!mounted) {
        return;
      }
      setState(() {
        _isVisible = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final double hudPadH = scaleDimension(context, 10);
    final double hudPadV = scaleDimension(context, 8);
    final double hudRadius = scaleDimension(context, 8);
    final double hudGap = scaleDimension(context, 8);
    final double swatchSize = scaleDimension(context, 12);
    return AnimatedOpacity(
      opacity: _isVisible ? 1 : 0,
      duration: _fadeDuration,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(hudRadius),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: hudPadH, vertical: hudPadV),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                "Telestrator ${widget.controller.isEnabled ? "On" : "Off"}",
                style: const TextStyle(color: Colors.white70),
              ),
              SizedBox(width: hudGap),
              Container(
                width: swatchSize,
                height: swatchSize,
                decoration: BoxDecoration(
                  color: widget.controller.activeColor,
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: hudGap),
              Text(
                "Brush ${widget.controller.brushSize.toStringAsFixed(0)}",
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayoutHelpOverlay extends StatelessWidget {
  const _PlayoutHelpOverlay();

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final double pad20 = scaleDimension(context, 20);
    final double gap12 = scaleDimension(context, 12);
    final double gap10 = scaleDimension(context, 10);
    final double maxHelpWidth = scaleDimension(context, 720);
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.65),
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxHelpWidth),
          child: Card(
            color: colorScheme.surface.withValues(alpha: 0.95),
            child: Padding(
              padding: EdgeInsets.all(pad20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    "Playout Hotkeys",
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  SizedBox(height: gap12),
                  _hotkeySection("Playback", <String, String>{
                    "Space": "Play/Pause",
                  }),
                  SizedBox(height: gap10),
                  _hotkeySection("Seek", <String, String>{
                    "Left / Right": "Seek 1s",
                    "Ctrl + Left / Right": "Seek 5s",
                    "Shift + Left / Right": "Seek 15s",
                    "Alt + Left / Right": "Seek 0.1s",
                  }),
                  SizedBox(height: gap10),
                  _hotkeySection("Volume", <String, String>{
                    "Up / Down": "Volume +/- 10%",
                    "M": "Toggle Mute",
                  }),
                  SizedBox(height: gap10),
                  _hotkeySection("Telestrator", <String, String>{
                    "T": "Toggle Telestrator",
                    "C": "Clear",
                    "Z": "Undo",
                    "1 / 2 / 3": "Set Color",
                    "[ / ]": "Brush Size Down/Up",
                  }),
                  SizedBox(height: gap10),
                  _hotkeySection("On-screen graphics", <String, String>{
                    "6 / 7 / 8 / 9 / 0": "Toggle OSG Presets 1 Through 5",
                  }),
                  SizedBox(height: gap10),
                  _hotkeySection("Exit and Help", <String, String>{
                    "Esc": "Exit Playout",
                    "H": "Toggle This Help",
                  }),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _hotkeySection(String title, Map<String, String> entries) {
    return Builder(
      builder: (BuildContext context) {
        final double gap6 = scaleDimension(context, 6);
        final double rowVertPad = scaleDimension(context, 2);
        final double keyColWidth = scaleDimension(context, 210);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            SizedBox(height: gap6),
            ...entries.entries.map(
              (MapEntry<String, String> item) => Padding(
                padding: EdgeInsets.symmetric(vertical: rowVertPad),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: keyColWidth,
                      child: Text(
                        item.key,
                        style: TextStyle(
                          fontFamily: "monospace",
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(child: Text(item.value)),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
