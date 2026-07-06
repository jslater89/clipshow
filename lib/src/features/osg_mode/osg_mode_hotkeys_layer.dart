import "package:flutter/material.dart";
import "package:flutter/services.dart";

import "package:obs_clipshow/src/osg/osg_models.dart";

class OsgModeToggleHelpIntent extends Intent {
  const OsgModeToggleHelpIntent();
}

class OsgModeOsgPresetSlotIntent extends Intent {
  const OsgModeOsgPresetSlotIntent(this.slot);
  final OsgPresetSlot slot;
}

class OsgModeTagSetQuickSlotIntent extends Intent {
  const OsgModeTagSetQuickSlotIntent(this.slotIndex);
  final int slotIndex;
}

class OsgModeHotkeysLayer extends StatelessWidget {
  const OsgModeHotkeysLayer({
    super.key,
    required this.child,
    required this.onExitRequested,
    required this.onHelpToggleRequested,
    required this.onOsgPresetSlotToggle,
    required this.onTagSetQuickSlot,
  });

  final Widget child;
  final Future<void> Function() onExitRequested;
  final VoidCallback onHelpToggleRequested;
  final ValueChanged<OsgPresetSlot> onOsgPresetSlotToggle;
  final ValueChanged<int> onTagSetQuickSlot;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.keyH):
            const OsgModeToggleHelpIntent(),
        const SingleActivator(LogicalKeyboardKey.digit1):
            const OsgModeTagSetQuickSlotIntent(0),
        const SingleActivator(LogicalKeyboardKey.digit2):
            const OsgModeTagSetQuickSlotIntent(1),
        const SingleActivator(LogicalKeyboardKey.digit3):
            const OsgModeTagSetQuickSlotIntent(2),
        const SingleActivator(LogicalKeyboardKey.digit4):
            const OsgModeTagSetQuickSlotIntent(3),
        const SingleActivator(LogicalKeyboardKey.digit5):
            const OsgModeTagSetQuickSlotIntent(4),
        const SingleActivator(LogicalKeyboardKey.digit6):
            const OsgModeOsgPresetSlotIntent(OsgPresetSlot.preset1),
        const SingleActivator(LogicalKeyboardKey.digit7):
            const OsgModeOsgPresetSlotIntent(OsgPresetSlot.preset2),
        const SingleActivator(LogicalKeyboardKey.digit8):
            const OsgModeOsgPresetSlotIntent(OsgPresetSlot.preset3),
        const SingleActivator(LogicalKeyboardKey.digit9):
            const OsgModeOsgPresetSlotIntent(OsgPresetSlot.preset4),
        const SingleActivator(LogicalKeyboardKey.digit0):
            const OsgModeOsgPresetSlotIntent(OsgPresetSlot.preset5),
        const SingleActivator(LogicalKeyboardKey.escape): const DismissIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          OsgModeToggleHelpIntent: CallbackAction<OsgModeToggleHelpIntent>(
            onInvoke: (_) {
              onHelpToggleRequested();
              return null;
            },
          ),
          OsgModeOsgPresetSlotIntent: CallbackAction<OsgModeOsgPresetSlotIntent>(
            onInvoke: (OsgModeOsgPresetSlotIntent intent) {
              onOsgPresetSlotToggle(intent.slot);
              return null;
            },
          ),
          OsgModeTagSetQuickSlotIntent:
              CallbackAction<OsgModeTagSetQuickSlotIntent>(
                onInvoke: (OsgModeTagSetQuickSlotIntent intent) {
                  onTagSetQuickSlot(intent.slotIndex);
                  return null;
                },
              ),
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              onExitRequested();
              return null;
            },
          ),
        },
        child: Focus(autofocus: true, child: child),
      ),
    );
  }
}
