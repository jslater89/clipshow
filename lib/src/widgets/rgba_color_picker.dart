import "package:flutter/material.dart";

import "package:obs_clipshow/src/app/ui_scale.dart";
import "package:obs_clipshow/src/widgets/checkerboard_background.dart";

/// Parses `#RRGGBB` (opaque) or `#AARRGGBB` into a 32-bit ARGB value, or null if invalid.
int? tryParseHexArgb(String raw) {
  String t = raw.trim();
  if (t.startsWith("#")) {
    t = t.substring(1);
  }
  if (t.length == 6) {
    final int? v = int.tryParse(t, radix: 16);
    if (v == null) {
      return null;
    }
    return 0xFF000000 | v;
  }
  if (t.length == 8) {
    final int? v = int.tryParse(t, radix: 16);
    if (v == null) {
      return null;
    }
    return v;
  }
  return null;
}

/// Uppercase `#AARRGGBB` for text fields.
String formatHexArgb(int argb) {
  final String h = (argb & 0xFFFFFFFF).toRadixString(16).padLeft(8, "0").toUpperCase();
  return "#$h";
}

class _ArgbComponents {
  const _ArgbComponents({
    required this.a,
    required this.r,
    required this.g,
    required this.b,
  });

  final int a;
  final int r;
  final int g;
  final int b;

  static _ArgbComponents fromArgb(int argb) {
    final int a = (argb >> 24) & 0xFF;
    final int r = (argb >> 16) & 0xFF;
    final int g = (argb >> 8) & 0xFF;
    final int b = argb & 0xFF;
    return _ArgbComponents(a: a, r: r, g: g, b: b);
  }

  int toArgb32() => Color.fromARGB(a, r, g, b).toARGB32();
}

/// Opens a dialog to pick an ARGB color (sliders + hex `#AARRGGBB`).
Future<int?> showRgbaColorPickerDialog(
  BuildContext context, {
  required int initialArgb,
}) {
  final _ArgbComponents start = _ArgbComponents.fromArgb(initialArgb);
  int a = start.a;
  int r = start.r;
  int g = start.g;
  int b = start.b;
  final TextEditingController hexController = TextEditingController(
    text: formatHexArgb(Color.fromARGB(a, r, g, b).toARGB32()),
  );
  return showDialog<int>(
    context: context,
    builder: (BuildContext context) {
      return StatefulBuilder(
        builder:
            (BuildContext context, void Function(void Function()) setState) {
          void syncFromArgb() {
            hexController.text = formatHexArgb(
              Color.fromARGB(a, r, g, b).toARGB32(),
            );
          }

          return AlertDialog(
            title: const Text("Pick Color"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SizedBox(
                    width: scaleDimension(context, 72),
                    height: scaleDimension(context, 72),
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        const CheckerboardBackground(divisions: 2),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: Color.fromARGB(a, r, g, b),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: scaleDimension(context, 8)),
                  TextField(
                    controller: hexController,
                    decoration: const InputDecoration(
                      labelText: "Hex (#AARRGGBB or #RRGGBB)",
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (String value) {
                      final int? parsed = tryParseHexArgb(value);
                      if (parsed == null) {
                        return;
                      }
                      final _ArgbComponents c = _ArgbComponents.fromArgb(
                        parsed,
                      );
                      setState(() {
                        a = c.a;
                        r = c.r;
                        g = c.g;
                        b = c.b;
                        syncFromArgb();
                      });
                    },
                  ),
                  SizedBox(height: scaleDimension(context, 4)),
                  Text(
                    "Alpha",
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  Slider(
                    value: a.toDouble(),
                    min: 0,
                    max: 255,
                    onChanged: (double value) => setState(() {
                      a = value.round();
                      syncFromArgb();
                    }),
                  ),
                  Text(
                    "Red",
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  Slider(
                    value: r.toDouble(),
                    min: 0,
                    max: 255,
                    onChanged: (double value) => setState(() {
                      r = value.round();
                      syncFromArgb();
                    }),
                  ),
                  Text(
                    "Green",
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  Slider(
                    value: g.toDouble(),
                    min: 0,
                    max: 255,
                    onChanged: (double value) => setState(() {
                      g = value.round();
                      syncFromArgb();
                    }),
                  ),
                  Text(
                    "Blue",
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  Slider(
                    value: b.toDouble(),
                    min: 0,
                    max: 255,
                    onChanged: (double value) => setState(() {
                      b = value.round();
                      syncFromArgb();
                    }),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text("Cancel"),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.of(context).pop(Color.fromARGB(a, r, g, b).toARGB32()),
                child: const Text("Use"),
              ),
            ],
          );
        },
      );
    },
  );
}

/// Opens [showRgbaColorPickerDialog] and invokes [onChanged] when the user confirms.
/// Tiny swatch-only control for dense toolbars (e.g. per-slot text color).
class RgbaMiniColorButton extends StatelessWidget {
  const RgbaMiniColorButton({
    super.key,
    required this.valueArgb,
    required this.onChanged,
    this.tooltip,
  });

  final int valueArgb;
  final ValueChanged<int> onChanged;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final Color outline = Theme.of(context).colorScheme.outline.withValues(
      alpha: 0.6,
    );
    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
      tooltip: tooltip ?? "Text color",
      onPressed: () async {
        final int? selected = await showRgbaColorPickerDialog(
          context,
          initialArgb: valueArgb,
        );
        if (selected != null) {
          onChanged(selected);
        }
      },
      icon: SizedBox(
        width: 16,
        height: 16,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            const CheckerboardBackground(divisions: 2),
            DecoratedBox(
              decoration: BoxDecoration(
                color: Color(valueArgb),
                border: Border.all(color: outline, width: 1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RgbaColorPickerButton extends StatelessWidget {
  const RgbaColorPickerButton({
    super.key,
    required this.label,
    required this.valueArgb,
    required this.onChanged,
  });

  final String label;
  final int valueArgb;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: () async {
        final int? selected = await showRgbaColorPickerDialog(
          context,
          initialArgb: valueArgb,
        );
        if (selected != null) {
          onChanged(selected);
        }
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: scaleDimension(context, 20),
            height: scaleDimension(context, 20),
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                const CheckerboardBackground(divisions: 2),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(valueArgb),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: scaleDimension(context, 8)),
          Text(label),
        ],
      ),
    );
  }
}
