import "package:flutter/material.dart";
import "package:provider/provider.dart";

import "package:obs_clipshow/src/features/dashboard/dashboard_view_model.dart";
import "package:obs_clipshow/src/features/dashboard/widgets/dashboard_shared_helpers.dart";

class DashboardCapturePanel extends StatefulWidget {
  const DashboardCapturePanel({super.key});

  @override
  State<DashboardCapturePanel> createState() => _DashboardCapturePanelState();
}

class _DashboardCapturePanelState extends State<DashboardCapturePanel> {
  TextEditingController? _activeCaptureTagInputController;
  bool _handledAutocompleteSelection = false;

  @override
  Widget build(BuildContext context) {
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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text("OBS Capture", style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                obsReady
                    ? "Tags are applied when you stop recording."
                    : "Enable OBS in Workspace Settings to use capture.",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final String tag in sortedCaptureTags)
                    InputChip(
                      label: Text(tag),
                      backgroundColor: tagChipColor(context, tag),
                      onDeleted: () => viewModel.removeCaptureTag(tag),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
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
                        _activeCaptureTagInputController = textEditingController;
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
                            _submitCaptureTag(viewModel, textEditingController);
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
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
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  FilledButton.icon(
                    onPressed: canStart
                        ? () => viewModel.startObsCapture()
                        : null,
                    icon: const Icon(Icons.fiber_manual_record),
                    label: const Text("Start Recording"),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.tonalIcon(
                    onPressed: canStop
                        ? () => viewModel.stopObsCaptureAndIngestTags()
                        : null,
                    icon: const Icon(Icons.stop),
                    label: const Text("Stop And Save"),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (viewModel.captureStatusMessage != null)
                Text(
                  viewModel.captureStatusMessage!,
                  style: theme.textTheme.bodyMedium,
                ),
            ],
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
