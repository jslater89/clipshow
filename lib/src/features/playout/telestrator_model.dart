import "dart:ui";

import "package:flutter/foundation.dart";

class TelestratorStroke {
  TelestratorStroke({
    required this.color,
    required this.width,
    required List<Offset> points,
  }) : points = List<Offset>.from(points);

  final Color color;
  final double width;
  final List<Offset> points;
}

class TelestratorController extends ChangeNotifier {
  static const double minBrushSize = 2;
  static const double maxBrushSize = 24;
  static const double brushStep = 2;

  bool _isEnabled = false;
  Color _activeColor = const Color(0xFFFF3B30);
  double _brushSize = 6;
  final List<TelestratorStroke> _strokes = <TelestratorStroke>[];
  final List<TelestratorStroke> _redoStack = <TelestratorStroke>[];
  TelestratorStroke? _activeStroke;

  bool get isEnabled => _isEnabled;
  Color get activeColor => _activeColor;
  double get brushSize => _brushSize;
  List<TelestratorStroke> get strokes =>
      List<TelestratorStroke>.unmodifiable(_strokes);

  void toggleEnabled() {
    _isEnabled = !_isEnabled;
    notifyListeners();
  }

  void startStroke(Offset point) {
    if (!_isEnabled) {
      return;
    }
    _redoStack.clear();
    final TelestratorStroke stroke = TelestratorStroke(
      color: _activeColor,
      width: _brushSize,
      points: <Offset>[point],
    );
    _activeStroke = stroke;
    _strokes.add(stroke);
    notifyListeners();
  }

  void appendPoint(Offset point) {
    final TelestratorStroke? stroke = _activeStroke;
    if (!_isEnabled || stroke == null) {
      return;
    }
    stroke.points.add(point);
    notifyListeners();
  }

  void endStroke() {
    if (_activeStroke == null) {
      return;
    }
    _activeStroke = null;
    notifyListeners();
  }

  void clear() {
    _activeStroke = null;
    _redoStack
      ..clear()
      ..addAll(_strokes);
    _strokes.clear();
    notifyListeners();
  }

  void undo() {
    if (_strokes.isEmpty) {
      return;
    }
    final TelestratorStroke removed = _strokes.removeLast();
    _redoStack.add(removed);
    notifyListeners();
  }

  void setColor(Color color) {
    _activeColor = color;
    notifyListeners();
  }

  /// Initial paint color, stroke width, and whether drawing is on (from workspace settings).
  void applyInitialTelestratorSettings({
    required Color activeColor,
    required double brushSize,
    required bool enabledByDefault,
  }) {
    _activeColor = activeColor;
    _brushSize = brushSize.clamp(minBrushSize, maxBrushSize);
    _isEnabled = enabledByDefault;
    notifyListeners();
  }

  void increaseBrush() {
    _brushSize = (_brushSize + brushStep).clamp(minBrushSize, maxBrushSize);
    notifyListeners();
  }

  void decreaseBrush() {
    _brushSize = (_brushSize - brushStep).clamp(minBrushSize, maxBrushSize);
    notifyListeners();
  }
}
