import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:provider/provider.dart";

import "package:obs_clipshow/src/app/ui_scale.dart";
import "package:obs_clipshow/src/features/dashboard/dashboard_view_model.dart";
import "package:obs_clipshow/src/features/dashboard/widgets/dashboard_shared_helpers.dart";

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

class _DashboardCapturePanelState extends State<DashboardCapturePanel> {
  TextEditingController? _activeCaptureTagInputController;
  bool _handledAutocompleteSelection = false;

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
    final List<String> sortedCaptureTags = sortTags(
      List<String>.from(viewModel.captureTags),
    );

    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.keyR): _StartCaptureIntent(),
        SingleActivator(LogicalKeyboardKey.keyS): _StopCaptureIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _StartCaptureIntent: CallbackAction<_StartCaptureIntent>(
            onInvoke: (_) {
              if (canStart) {
                viewModel.startObsCapture();
              }
              return null;
            },
          ),
          _StopCaptureIntent: CallbackAction<_StopCaptureIntent>(
            onInvoke: (_) {
              if (canStop) {
                viewModel.stopObsCaptureAndIngestTags();
              }
              return null;
            },
          ),
        },
        child: Focus(
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
                        for (final String tag in sortedCaptureTags)
                          InputChip(
                            label: Text(tag),
                            backgroundColor: tagChipColor(context, tag),
                            onDeleted: () => viewModel.removeCaptureTag(tag),
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
                            },
                            fieldViewBuilder: (
                              BuildContext context,
                              TextEditingController textEditingController,
                              FocusNode focusNode,
                              VoidCallback onFieldSubmitted,
                            ) {
                              _activeCaptureTagInputController =
                                  textEditingController;
                              return TextField(
                                controller: textEditingController,
                                focusNode: focusNode,
                                decoration: const InputDecoration(
                                  labelText: "Add Tag",
                                  border: OutlineInputBorder(),
                                ),
                                onSubmitted: (_) {
                                  onFieldSubmitted();
                                  if (_handledAutocompleteSelection) {
                                    _handledAutocompleteSelection = false;
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
      return;
    }
    viewModel.addCaptureTag(tag);
    controller.clear();
  }
}
