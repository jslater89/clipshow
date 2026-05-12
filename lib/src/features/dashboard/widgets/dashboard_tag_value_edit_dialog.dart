import "package:flutter/material.dart";

import "package:obs_clipshow/src/features/dashboard/dashboard_view_model.dart";
import "package:obs_clipshow/src/features/dashboard/widgets/dashboard_shared_helpers.dart";

/// Dialog to rename or replace a tag string, with the same library tag
/// suggestions as other tag fields ([DashboardViewModel.tagSuggestionsFor]).
Future<String?> showTagValueEditDialog({
  required BuildContext context,
  required DashboardViewModel viewModel,
  required String initialTagText,
}) async {
  final String? result = await showDialog<String>(
    context: context,
    builder: (BuildContext ctx) => _TagValueEditDialog(
      viewModel: viewModel,
      initialTagText: initialTagText,
    ),
  );
  return result?.trim();
}

class _TagValueEditDialog extends StatefulWidget {
  const _TagValueEditDialog({
    required this.viewModel,
    required this.initialTagText,
  });

  final DashboardViewModel viewModel;
  final String initialTagText;

  @override
  State<_TagValueEditDialog> createState() => _TagValueEditDialogState();
}

class _TagValueEditDialogState extends State<_TagValueEditDialog> {
  TextEditingController? _fieldController;
  bool _seededInitial = false;

  void _popWithCurrentText(BuildContext dialogContext) {
    final String raw = _fieldController?.text ?? "";
    Navigator.of(dialogContext).pop<String>(raw);
  }

  @override
  Widget build(BuildContext context) {
    final double maxW = MediaQuery.sizeOf(context).width - 48;
    return AlertDialog(
      title: const Text("Edit Tag Value"),
      content: SizedBox(
        width: maxW.clamp(280, 420),
        child: AdaptiveAutocomplete<String>(
          optionsBuilder: (TextEditingValue textEditingValue) {
            return widget.viewModel.tagSuggestionsFor(textEditingValue.text);
          },
          onSelected: (_) {},
          fieldViewBuilder: (
            BuildContext context,
            TextEditingController textEditingController,
            FocusNode focusNode,
            VoidCallback onFieldSubmitted,
          ) {
            _fieldController = textEditingController;
            if (!_seededInitial) {
              _seededInitial = true;
              if (widget.initialTagText.isNotEmpty) {
                textEditingController.text = widget.initialTagText;
                textEditingController.selection = TextSelection.collapsed(
                  offset: textEditingController.text.length,
                );
              }
            }
            return TextField(
              controller: textEditingController,
              focusNode: focusNode,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: "Tag Text",
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) {
                onFieldSubmitted();
                _popWithCurrentText(context);
              },
            );
          },
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop<String>(),
          child: const Text("Cancel"),
        ),
        FilledButton(
          onPressed: () => _popWithCurrentText(context),
          child: const Text("Save"),
        ),
      ],
    );
  }
}
