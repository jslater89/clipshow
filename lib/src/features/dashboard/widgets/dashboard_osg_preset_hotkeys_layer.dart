import "package:flutter/material.dart";
import "package:flutter/services.dart";

import "package:obs_clipshow/src/features/dashboard/widgets/dashboard_preview_hotkeys_layer.dart";
import "package:obs_clipshow/src/osg/osg_models.dart";

/// Top-row and numpad digit shortcuts for OSG preset slots 6–0.
Map<ShortcutActivator, Intent> osgPresetSlotShortcutMap() {
  return <ShortcutActivator, Intent>{
    const SingleActivator(LogicalKeyboardKey.digit6):
        const PreviewOsgPresetSlotIntent(OsgPresetSlot.preset1),
    const SingleActivator(LogicalKeyboardKey.digit7):
        const PreviewOsgPresetSlotIntent(OsgPresetSlot.preset2),
    const SingleActivator(LogicalKeyboardKey.digit8):
        const PreviewOsgPresetSlotIntent(OsgPresetSlot.preset3),
    const SingleActivator(LogicalKeyboardKey.digit9):
        const PreviewOsgPresetSlotIntent(OsgPresetSlot.preset4),
    const SingleActivator(LogicalKeyboardKey.digit0):
        const PreviewOsgPresetSlotIntent(OsgPresetSlot.preset5),
    const SingleActivator(LogicalKeyboardKey.numpad6):
        const PreviewOsgPresetSlotIntent(OsgPresetSlot.preset1),
    const SingleActivator(LogicalKeyboardKey.numpad7):
        const PreviewOsgPresetSlotIntent(OsgPresetSlot.preset2),
    const SingleActivator(LogicalKeyboardKey.numpad8):
        const PreviewOsgPresetSlotIntent(OsgPresetSlot.preset3),
    const SingleActivator(LogicalKeyboardKey.numpad9):
        const PreviewOsgPresetSlotIntent(OsgPresetSlot.preset4),
    const SingleActivator(LogicalKeyboardKey.numpad0):
        const PreviewOsgPresetSlotIntent(OsgPresetSlot.preset5),
  };
}

/// Captures 6–0 (and numpad) for toggling OSG preset visibility in preview.
class DashboardOsgPresetHotkeysLayer extends StatelessWidget {
  const DashboardOsgPresetHotkeysLayer({
    super.key,
    required this.child,
    required this.focusNode,
    required this.onOsgPresetSlotToggle,
    this.autofocus = false,
  });

  final Widget child;
  final FocusNode focusNode;
  final ValueChanged<OsgPresetSlot> onOsgPresetSlotToggle;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: osgPresetSlotShortcutMap(),
      child: Actions(
        actions: <Type, Action<Intent>>{
          PreviewOsgPresetSlotIntent:
              CallbackAction<PreviewOsgPresetSlotIntent>(
                onInvoke: (PreviewOsgPresetSlotIntent intent) {
                  onOsgPresetSlotToggle(intent.slot);
                  return null;
                },
              ),
        },
        child: Focus(
          focusNode: focusNode,
          autofocus: autofocus,
          canRequestFocus: true,
          child: child,
        ),
      ),
    );
  }
}
