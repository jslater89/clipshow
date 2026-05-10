import "package:flutter/widgets.dart";

const double kMinUiScale = 0.8;
const double kMaxUiScale = 1.6;
const double kUiScaleStep = 0.1;

class UiScaleScope extends InheritedWidget {
  const UiScaleScope({
    required super.child,
    required this.scale,
    required this.increaseScale,
    required this.decreaseScale,
    super.key,
  });

  final double scale;
  final VoidCallback increaseScale;
  final VoidCallback decreaseScale;

  static UiScaleScope maybeOf(BuildContext context) {
    final UiScaleScope? scope =
        context.dependOnInheritedWidgetOfExactType<UiScaleScope>();
    if (scope != null) {
      return scope;
    }
    return const UiScaleScope(
      scale: 1,
      increaseScale: _noop,
      decreaseScale: _noop,
      child: SizedBox.shrink(),
    );
  }

  static void _noop() {}

  @override
  bool updateShouldNotify(covariant UiScaleScope oldWidget) {
    return scale != oldWidget.scale;
  }
}

double uiScaleFactor(BuildContext context) {
  return UiScaleScope.maybeOf(context).scale;
}

double scaleDimension(BuildContext context, double value) {
  return value * uiScaleFactor(context);
}
