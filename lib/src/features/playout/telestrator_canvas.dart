import "package:flutter/material.dart";

import 'package:obs_clipshow/src/features/playout/telestrator_model.dart';

class TelestratorCanvas extends StatelessWidget {
  const TelestratorCanvas({super.key, required this.controller});

  final TelestratorController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? child) {
        return IgnorePointer(
          ignoring: !controller.isEnabled,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: (DragStartDetails details) {
              controller.startStroke(details.localPosition);
            },
            onPanUpdate: (DragUpdateDetails details) {
              controller.appendPoint(details.localPosition);
            },
            onPanEnd: (_) {
              controller.endStroke();
            },
            onPanCancel: controller.endStroke,
            child: CustomPaint(
              painter: _TelestratorPainter(strokes: controller.strokes),
              child: const SizedBox.expand(),
            ),
          ),
        );
      },
    );
  }
}

class _TelestratorPainter extends CustomPainter {
  _TelestratorPainter({required this.strokes});

  final List<TelestratorStroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final TelestratorStroke stroke in strokes) {
      if (stroke.points.isEmpty) {
        continue;
      }
      final Paint paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = stroke.width
        ..color = stroke.color;

      if (stroke.points.length == 1) {
        canvas.drawCircle(stroke.points.single, stroke.width / 2, paint);
        continue;
      }

      final Path path = Path()
        ..moveTo(stroke.points.first.dx, stroke.points.first.dy);
      for (int index = 1; index < stroke.points.length; index++) {
        final Offset point = stroke.points[index];
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TelestratorPainter oldDelegate) {
    return oldDelegate.strokes != strokes;
  }
}
