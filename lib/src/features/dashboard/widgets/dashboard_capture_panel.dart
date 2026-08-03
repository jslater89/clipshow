import "dart:async";

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:provider/provider.dart";

import "package:obs_clipshow/src/app/ui_scale.dart";
import "package:obs_clipshow/src/features/dashboard/dashboard_view_model.dart";
import "package:obs_clipshow/src/features/dashboard/widgets/dashboard_media_tag_menu.dart";
import "package:obs_clipshow/src/features/dashboard/widgets/dashboard_shared_helpers.dart";
import "package:obs_clipshow/src/osg/osg_models.dart";

class DashboardCapturePanel extends StatefulWidget {
  const DashboardCapturePanel({super.key});

  @override
  State<DashboardCapturePanel> createState() => _DashboardCapturePanelState();
}

class _StartCaptureIntent extends Intent {
  const _StartCaptureIntent();
}

class _StopCaptureIntent extends Intent {
  const _StopCaptureIntent();
}

/// Capture letter hotkeys; disabled while [tagFieldHasFocus] so Add Tag can
/// type "r" / "s". [Shortcuts] resolves [Actions] from [primaryFocus], so the
/// panel [FocusNode] must hold focus whenever the tag field does not.
class _CaptureHotkeyAction<T extends Intent> extends Action<T> {
  _CaptureHotkeyAction({
    required this.tagFieldHasFocus,
    required this.onInvoke,
  });

  final bool Function() tagFieldHasFocus;
  final VoidCallback onInvoke;

  @override
  bool isEnabled(T intent) => !tagFieldHasFocus();

  @override
  bool consumesKey(T intent) => isEnabled(intent);

  @override
  Object? invoke(T intent) {
    onInvoke();
    return null;
  }
}

class _DashboardCapturePanelState extends State<DashboardCapturePanel> {
  final FocusNode _panelFocus = FocusNode(debugLabel: "CapturePanel");
  TextEditingController? _activeCaptureTagInputController;
  FocusNode? _tagFieldFocus;
  bool _handledAutocompleteSelection = false;

  bool _tagFieldHasFocus() => _tagFieldFocus?.hasFocus ?? false;

  void _bindTagFieldFocus(FocusNode focusNode) {
    if (identical(_tagFieldFocus, focusNode)) {
      return;
    }
    _tagFieldFocus?.removeListener(_onTagFieldFocusChange);
    _tagFieldFocus = focusNode;
    _tagFieldFocus!.addListener(_onTagFieldFocusChange);
  }

  void _onTagFieldFocusChange() {
    if (!mounted) {
      return;
    }
    // Shortcuts looks up Actions from primaryFocus; keep the panel node
    // focused whenever the tag field is not editing.
    if (!_tagFieldHasFocus() && !_panelFocus.hasFocus) {
      _panelFocus.requestFocus();
    }
  }

  void _focusPanel() {
    _panelFocus.requestFocus();
  }

  @override
  void dispose() {
    _tagFieldFocus?.removeListener(_onTagFieldFocusChange);
    _panelFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double pad12 = scaleDimension(context, 12);
    final double gap8 = scaleDimension(context, 8);
    final double gap10 = scaleDimension(context, 10);
    final double gap16 = scaleDimension(context, 16);
    final DashboardViewModel viewModel = context.watch<DashboardViewModel>();
    final ThemeData theme = Theme.of(context);
    final bool obsReady =
        viewModel.obsSceneSwitchConfig != null &&
        viewModel.obsSceneSwitchConfig!.enabled;
    final bool canStart =
        obsReady &&
        !viewModel.obsCaptureRecording &&
        viewModel.workspacePath != null;
    final bool canStop = viewModel.obsCaptureRecording;
    final List<ShelfTagEntry> sortedCaptureTags = sortShelfTagEntries(
      List<ShelfTagEntry>.from(viewModel.captureTags),
    );

    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.keyR): _StartCaptureIntent(),
        SingleActivator(LogicalKeyboardKey.keyS): _StopCaptureIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _StartCaptureIntent: _CaptureHotkeyAction<_StartCaptureIntent>(
            tagFieldHasFocus: _tagFieldHasFocus,
            onInvoke: () {
              if (canStart) {
                viewModel.startObsCapture();
              }
            },
          ),
          _StopCaptureIntent: _CaptureHotkeyAction<_StopCaptureIntent>(
            tagFieldHasFocus: _tagFieldHasFocus,
            onInvoke: () {
              if (canStop) {
                viewModel.stopObsCaptureAndIngestTags();
              }
            },
          ),
        },
        child: Focus(
          focusNode: _panelFocus,
          autofocus: true,
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(pad12),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text("OBS Capture", style: theme.textTheme.titleMedium),
                    SizedBox(height: gap8),
                    Text(
                      obsReady
                          ? "Tags are applied when you stop recording."
                          : "Enable OBS in Workspace Settings to use capture.",
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    SizedBox(height: gap16),
                    Wrap(
                      spacing: gap8,
                      runSpacing: gap8,
                      children: <Widget>[
                        for (final ShelfTagEntry e in sortedCaptureTags)
                          GestureDetector(
                            onSecondaryTapUp: (TapUpDetails d) {
                              unawaited(
                                showShelfTagContextMenu(
                                  context: context,
                                  viewModel: viewModel,
                                  entry: e,
                                  target: DashboardShelfTagMenuTarget.capture,
                                  globalPosition: d.globalPosition,
                                ),
                              );
                            },
                            child: InputChip(
                              label: shelfTagChipLabel(
                                e,
                                viewModel.tagSemanticTypes,
                              ),
                              backgroundColor: tagChipColor(context, e.name),
                              onDeleted: () =>
                                  viewModel.removeCaptureTag(e.name),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: gap10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: <Widget>[
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: scaleDimension(context, 400),
                          ),
                          child: AdaptiveAutocomplete<String>(
                            optionsBuilder: (TextEditingValue textEditingValue) {
                              return viewModel.tagSuggestionsFor(
                                textEditingValue.text,
                              );
                            },
                            onSelected: (String value) {
                              _handledAutocompleteSelection = true;
                              viewModel.addCaptureTag(value);
                              _activeCaptureTagInputController?.clear();
                              _focusPanel();
                            },
                            fieldViewBuilder: (
                              BuildContext context,
                              TextEditingController textEditingController,
                              FocusNode focusNode,
                              VoidCallback onFieldSubmitted,
                            ) {
                              _activeCaptureTagInputController =
                                  textEditingController;
                              _bindTagFieldFocus(focusNode);
                              return TextField(
                                controller: textEditingController,
                                focusNode: focusNode,
                                decoration: const InputDecoration(
                                  labelText: "Add Tag",
                                  border: OutlineInputBorder(),
                                ),
                                onTapOutside: (_) {
                                  focusNode.unfocus();
                                  _focusPanel();
                                },
                                onSubmitted: (_) {
                                  onFieldSubmitted();
                                  if (_handledAutocompleteSelection) {
                                    _handledAutocompleteSelection = false;
                                    _focusPanel();
                                    return;
                                  }
                                  _submitCaptureTag(
                                    viewModel,
                                    textEditingController,
                                  );
                                },
                              );
                            },
                          ),
                        ),
                        SizedBox(width: gap8),
                        FilledButton(
                          onPressed: () {
                            final TextEditingController? controller =
                                _activeCaptureTagInputController;
                            if (controller == null) {
                              return;
                            }
                            _submitCaptureTag(viewModel, controller);
                          },
                          child: const Text("Add"),
                        ),
                      ],
                    ),
                    SizedBox(height: gap16),
                    Row(
                      children: <Widget>[
                        FilledButton.icon(
                          onPressed: canStart
                              ? () => viewModel.startObsCapture()
                              : null,
                          icon: const Icon(Icons.fiber_manual_record),
                          label: const Text("(r) Start Recording"),
                        ),
                        SizedBox(width: pad12),
                        FilledButton.tonalIcon(
                          onPressed: canStop
                              ? () => viewModel.stopObsCaptureAndIngestTags()
                              : null,
                          icon: const Icon(Icons.stop),
                          label: const Text("(s) Stop And Save"),
                        ),
                      ],
                    ),
                    SizedBox(height: gap16),
                    if (viewModel.captureStatusMessage != null)
                      Text(
                        viewModel.captureStatusMessage!,
                        style: theme.textTheme.bodyMedium,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _submitCaptureTag(
    DashboardViewModel viewModel,
    TextEditingController controller,
  ) {
    final String tag = controller.text.trim();
    if (tag.isEmpty) {
      _focusPanel();
      return;
    }
    viewModel.addCaptureTag(tag);
    controller.clear();
    _focusPanel();
  }
}
