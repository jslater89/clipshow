import "dart:math" as math;

import "package:flutter/foundation.dart";
import "package:flutter/material.dart";

/// Playout compositing shim via root [OverlayEntry].
///
/// Mimics [BannerPainter] (foreground shadow + semi-transparent fill) with
/// tunable constants below. A 1px opaque strip in this slot does not fix the
/// FVP/Linux chroma bug; this corner paint path does. Used for playout and
/// OSG Mode on Linux.
///
/// Painted in all four corners to nudge the compositor off a broken fast path
/// (small transparent PNGs / non-layer alpha) onto a working slow path—large
/// or permanently layer-opaque OSGs rarely need this.
const bool kPlayoutFrameworkRootCompositingStrip = true;

/// Diagonal strip half-width before rotation (~Banner `_kOffset`).
const double kPlayoutCompositingShimCornerOffset = 1;

/// Strip thickness before rotation (~Banner `_kHeight`).
const double kPlayoutCompositingShimStripHeight = 1;

/// Semi-transparent fill on the corner strip.
const Color kPlayoutCompositingShimFillColor = Color.fromARGB(1, 109, 109, 109);

/// Blurred shadow drawn under the strip ([Banner] default blur is 6).
const Color kPlayoutCompositingShimShadowColor = Color.fromARGB(1, 109, 109, 109);
const double kPlayoutCompositingShimShadowBlur = 1;

const bool kPlayoutCompositingShimDrawShadow = true;
const bool kPlayoutCompositingShimDrawFill = false;

/// Inserts a root compositing shim overlay for the duration of playout.
class PlayoutRootCompositingOverlay {
  OverlayEntry? _entry;
  int _mountAttempts = 0;
  static const int _maxMountAttempts = 12;

  void resetMountAttempts() {
    _mountAttempts = 0;
  }

  void mountFromNavigator(GlobalKey<NavigatorState> navigatorKey) {
    if (!kPlayoutFrameworkRootCompositingStrip) {
      return;
    }
    final NavigatorState? navigator = navigatorKey.currentState;
    final OverlayState? overlay = navigator?.overlay;
    if (overlay == null) {
      if (_mountAttempts < _maxMountAttempts) {
        _mountAttempts++;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          mountFromNavigator(navigatorKey);
        });
      } else if (kDebugMode) {
        debugPrint(
          "PlayoutRootCompositingOverlay: navigator overlay unavailable "
          "after $_maxMountAttempts frames",
        );
      }
      return;
    }

    _mountAttempts = 0;
    if (_entry != null) {
      unmount();
    }

    _entry = OverlayEntry(
      opaque: false,
      maintainState: true,
      builder: (BuildContext context) {
        return const _PlayoutRootCompositingShimOverlay();
      },
    );
    overlay.insert(_entry!);
  }

  void unmount() {
    _mountAttempts = 0;
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
  }
}

class _PlayoutRootCompositingShimOverlay extends StatelessWidget {
  const _PlayoutRootCompositingShimOverlay();

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.sizeOf(context);
    return Positioned(
      left: 0,
      top: 0,
      width: size.width,
      height: size.height,
      child: IgnorePointer(
        child: CustomPaint(
          foregroundPainter: const _PlayoutCompositingCornerPainter(),
          child: SizedBox(
            width: size.width,
            height: size.height,
          ),
        ),
      ),
    );
  }
}

/// Minimal [BannerPainter]-style corner paint in all four corners.
class _PlayoutCompositingCornerPainter extends CustomPainter {
  const _PlayoutCompositingCornerPainter();

  /// Origin + rotation for each corner, matching Flutter [BannerLocation] LTR
  /// transforms (topStart / topEnd / bottomStart / bottomEnd).
  static const List<({double dxFactor, double dyFactor, double rotation})>
      _corners = <({double dxFactor, double dyFactor, double rotation})>[
    (dxFactor: 0, dyFactor: 0, rotation: -math.pi / 4), // top-start
    (dxFactor: 1, dyFactor: 0, rotation: math.pi / 4), // top-end
    (dxFactor: 0, dyFactor: 1, rotation: -math.pi / 4), // bottom-start
    (dxFactor: 1, dyFactor: 1, rotation: math.pi / 4), // bottom-end
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final double offset = kPlayoutCompositingShimCornerOffset;
    final double height = kPlayoutCompositingShimStripHeight;
    final Rect stripRect = Rect.fromLTWH(
      -offset,
      offset - height,
      offset * 2,
      height,
    );

    Paint? shadowPaint;
    if (kPlayoutCompositingShimDrawShadow) {
      shadowPaint = Paint()
        ..color = kPlayoutCompositingShimShadowColor
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          kPlayoutCompositingShimShadowBlur,
        );
    }
    Paint? fillPaint;
    if (kPlayoutCompositingShimDrawFill) {
      fillPaint = Paint()..color = kPlayoutCompositingShimFillColor;
    }

    for (final ({double dxFactor, double dyFactor, double rotation}) corner
        in _corners) {
      canvas.save();
      canvas.translate(
        corner.dxFactor * size.width,
        corner.dyFactor * size.height,
      );
      canvas.rotate(corner.rotation);
      if (shadowPaint != null) {
        canvas.drawRect(stripRect, shadowPaint);
      }
      if (fillPaint != null) {
        canvas.drawRect(stripRect, fillPaint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _PlayoutCompositingCornerPainter oldDelegate) {
    return false;
  }
}
