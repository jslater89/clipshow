import "package:flutter/material.dart";

import "package:obs_clipshow/src/features/osg/widgets/osg_semantic_type_icon_catalog.dart";

/// Sentinel returned when the user chooses to remove the icon.
final class OsgSemanticIconClear {
  const OsgSemanticIconClear();
}

const OsgSemanticIconClear osgSemanticIconClear = OsgSemanticIconClear();

/// Returns [IconData] when chosen, [osgSemanticIconClear] when cleared, or `null` when cancelled.
Future<Object?> showOsgSemanticTypeIconPicker(BuildContext context) {
  return showDialog<Object?>(
    context: context,
    builder: (BuildContext ctx) => const _OsgSemanticTypeIconPickerDialog(),
  );
}

class _OsgSemanticTypeIconPickerDialog extends StatefulWidget {
  const _OsgSemanticTypeIconPickerDialog();

  @override
  State<_OsgSemanticTypeIconPickerDialog> createState() =>
      _OsgSemanticTypeIconPickerDialogState();
}

class _OsgSemanticTypeIconPickerDialogState
    extends State<_OsgSemanticTypeIconPickerDialog> {
  final TextEditingController _filter = TextEditingController();
  String _q = "";

  @override
  void initState() {
    super.initState();
    _filter.addListener(() {
      setState(() {
        _q = _filter.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<(String, IconData)> filtered = _q.isEmpty
        ? osgSemanticTypeIconChoices
        : osgSemanticTypeIconChoices
              .where(((String, IconData) e) => e.$1.toLowerCase().contains(_q))
              .toList();

    return AlertDialog(
      title: const Text("Choose Icon"),
      content: SizedBox(
        width: 420,
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              controller: _filter,
              decoration: const InputDecoration(
                labelText: "Search",
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 6,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemCount: filtered.length,
                itemBuilder: (BuildContext context, int i) {
                  final (String label, IconData icon) = filtered[i];
                  return Tooltip(
                    message: label,
                    child: InkWell(
                      onTap: () => Navigator.pop(context, icon),
                      borderRadius: BorderRadius.circular(8),
                      child: Icon(icon, size: 28),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context, osgSemanticIconClear),
          child: const Text("Clear Icon"),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
      ],
    );
  }
}

IconData osgMaterialIconFromCodePoint(int codePoint) {
  return IconData(codePoint, fontFamily: "MaterialIcons");
}
