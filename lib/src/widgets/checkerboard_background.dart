import "package:flutter/material.dart";

/// Paints a fixed-count checker grid over the full bounds (same scheme as common
/// transparency swatches).
class CheckerboardPainter extends CustomPainter {
  const CheckerboardPainter({
    this.divisions = 8,
    this.light = const Color(0xFFE0E0E0),
    this.dark = const Color(0xFFBDBDBD),
  });

  final int divisions;
  final Color light;
  final Color dark;

  @override
  void paint(Canvas canvas, Size size) {
    final int n = divisions.clamp(1, 64);
    final double cw = size.width / n;
    final double ch = size.height / n;
    final Paint lightPaint = Paint()..color = light;
    final Paint darkPaint = Paint()..color = dark;
    for (int yi = 0; yi < n; yi++) {
      for (int xi = 0; xi < n; xi++) {
        final Rect cell = Rect.fromLTWH(
          xi * cw,
          yi * ch,
          cw,
          ch,
        );
        canvas.drawRect(
          cell,
          (xi + yi).isEven ? lightPaint : darkPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CheckerboardPainter oldDelegate) {
    return oldDelegate.divisions != divisions ||
        oldDelegate.light != light ||
        oldDelegate.dark != dark;
  }
}

/// Fills its parent; place under translucent layers (e.g. OSG previews).
class CheckerboardBackground extends StatelessWidget {
  const CheckerboardBackground({
    super.key,
    this.divisions = 8,
    this.light = const Color(0xFFE0E0E0),
    this.dark = const Color(0xFFBDBDBD),
  });

  final int divisions;
  final Color light;
  final Color dark;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: CheckerboardPainter(
        divisions: divisions,
        light: light,
        dark: dark,
      ),
      child: const SizedBox.expand(),
    );
  }
}
