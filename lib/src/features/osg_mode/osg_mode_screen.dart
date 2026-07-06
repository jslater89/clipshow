import "package:flutter/material.dart";
import "package:logging/logging.dart";

import "package:obs_clipshow/src/app/ui_scale.dart";
import "package:obs_clipshow/src/features/osg_mode/osg_mode_hotkeys_layer.dart";
import "package:obs_clipshow/src/features/osg_mode/osg_mode_session.dart";
import "package:obs_clipshow/src/features/playout/osg_playout_layer.dart";
import "package:obs_clipshow/src/widgets/transient_hud_banner.dart";
import "package:obs_clipshow/src/media/media_list_item.dart";
import "package:obs_clipshow/src/osg/osg_models.dart";

typedef OsgSemanticResolve = Future<String?> Function(int semanticTypeId);

class OsgModeScreen extends StatefulWidget {
  const OsgModeScreen({
    super.key,
    required this.session,
    required this.keyColorArgb,
    required this.osgWorkspaceConfig,
    required this.workspaceRoot,
    required this.tagSemanticTypes,
    required this.onResolveSemanticText,
    required this.onExitRequested,
    required this.onFirstFrameReady,
    required this.onTagSetQuickSlot,
    required this.onSessionChanged,
  });

  final OsgModeSession session;
  final int keyColorArgb;
  final OsgWorkspaceConfig osgWorkspaceConfig;
  final String workspaceRoot;
  final List<TagSemanticType> tagSemanticTypes;
  final OsgSemanticResolve onResolveSemanticText;
  final Future<void> Function() onExitRequested;
  final VoidCallback onFirstFrameReady;
  final Future<OsgModeSession?> Function(int quickSlotIndex) onTagSetQuickSlot;
  final ValueChanged<OsgModeSession> onSessionChanged;

  @override
  State<OsgModeScreen> createState() => _OsgModeScreenState();
}

class _OsgModeScreenState extends State<OsgModeScreen> {
  final Logger _logger = Logger("OsgModeScreen");
  bool _isExiting = false;
  bool _showHelpOverlay = false;
  OsgPresetVisibility _osgPresetVisible = const OsgPresetVisibility.allOff();
  int _osgRequirementFlashToken = 0;
  String _osgRequirementFlashText = "";
  late OsgModeSession _session;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    final OsgPresetVisibility? initial = _session.osgPresetVisibleInitial;
    if (initial != null) {
      _osgPresetVisible = initial;
    }
    _reconcileOsgVisibilityToRequirements(requestFrame: false);
    _logger.info("OSG Mode started for tag set ${_session.tagSetName}");
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      widget.onFirstFrameReady();
    });
  }

  @override
  void didUpdateWidget(covariant OsgModeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.tagSetId != widget.session.tagSetId ||
        oldWidget.session.semanticTagSnapshotVersion !=
            widget.session.semanticTagSnapshotVersion ||
        !_semanticIdSetsEqual(
          oldWidget.session.semanticTypeIdsOnMedia,
          widget.session.semanticTypeIdsOnMedia,
        )) {
      _session = widget.session;
      _reconcileOsgVisibilityToRequirements();
    }
  }

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
    final Set<int> onMedia = _session.semanticTypeIdsOnMedia;
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
    if (next &&
        preset.requiredSemanticTypeIds.isNotEmpty &&
        !preset.semanticRequirementsSatisfiedBy(_session.semanticTypeIdsOnMedia)) {
      _flashOsgRequirementMessage(
        osgMissingSemanticRequirementsMessage(
          preset: preset,
          semanticTypeIdsOnMedia: _session.semanticTypeIdsOnMedia,
          tagSemanticTypes: widget.tagSemanticTypes,
        ),
      );
      return;
    }
    setState(() {
      _osgPresetVisible = _osgPresetVisible.withSlot(slot, next);
    });
  }

  Future<void> _requestExit() async {
    if (_isExiting) {
      return;
    }
    _isExiting = true;
    await widget.onExitRequested();
  }

  Future<void> _switchTagSetQuickSlot(int slotIndex) async {
    final OsgModeSession? next = await widget.onTagSetQuickSlot(slotIndex);
    if (!mounted || next == null) {
      return;
    }
    setState(() {
      _session = next;
    });
    widget.onSessionChanged(next);
    _reconcileOsgVisibilityToRequirements();
  }

  void _toggleHelpOverlay() {
    setState(() {
      _showHelpOverlay = !_showHelpOverlay;
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double edgeInset = scaleDimension(context, 16);
    return Scaffold(
      backgroundColor: Color(widget.keyColorArgb),
      body: OsgModeHotkeysLayer(
        onExitRequested: _requestExit,
        onHelpToggleRequested: _toggleHelpOverlay,
        onOsgPresetSlotToggle: _toggleOsgPreset,
        onTagSetQuickSlot: _switchTagSetQuickSlot,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (widget.workspaceRoot.trim().isNotEmpty)
              OsgPlayoutLayer(
                key: ValueKey<String>(
                  "ts:${_session.tagSetId}-${_session.semanticTagSnapshotVersion}",
                ),
                mediaType: MediaListItemType.tagSet,
                mediaId: _session.tagSetId,
                annotationsText: _session.annotationsText,
                semanticTagSnapshotVersion: _session.semanticTagSnapshotVersion,
                config: widget.osgWorkspaceConfig,
                workspaceRoot: widget.workspaceRoot,
                resolveSemantic: widget.onResolveSemanticText,
                visible: _osgPresetVisible,
              ),
            if (_osgRequirementFlashToken > 0)
              Positioned(
                left: edgeInset,
                bottom: edgeInset,
                child: TransientHudBanner(
                  key: ValueKey<int>(_osgRequirementFlashToken),
                  text: _osgRequirementFlashText,
                  onDismissed: _clearOsgRequirementFlash,
                ),
              ),
            if (_showHelpOverlay) const _OsgModeHelpOverlay(),
          ],
        ),
      ),
    );
  }
}

class _OsgModeHelpOverlay extends StatelessWidget {
  const _OsgModeHelpOverlay();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xCC000000),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const <Widget>[
                  Text(
                    "OSG Mode Hotkeys",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 12),
                  Text("1–5 — Switch Tag Set Quick Slot"),
                  Text("6–0 — Toggle OSG Preset"),
                  Text("H — Toggle This Help"),
                  Text("Escape — Return to Dashboard"),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
