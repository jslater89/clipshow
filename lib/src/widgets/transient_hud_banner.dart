import "dart:async";

import "package:flutter/material.dart";

import "package:obs_clipshow/src/app/ui_scale.dart";

/// Short-lived pill matching playout telestrator HUD timing: hold then fade out.
class TransientHudBanner extends StatefulWidget {
  const TransientHudBanner({
    super.key,
    required this.text,
    this.onDismissed,
    this.textStyle,
  });

  final String text;
  final VoidCallback? onDismissed;
  final TextStyle? textStyle;

  @override
  State<TransientHudBanner> createState() => _TransientHudBannerState();
}

class _TransientHudBannerState extends State<TransientHudBanner> {
  static const Duration _hold = Duration(seconds: 1);
  static const Duration _fade = Duration(milliseconds: 220);

  Timer? _holdTimer;
  bool _opaque = true;

  @override
  void initState() {
    super.initState();
    _holdTimer = Timer(_hold, () {
      if (!mounted) {
        return;
      }
      setState(() {
        _opaque = false;
      });
      Future<void>.delayed(_fade, () {
        if (!mounted) {
          return;
        }
        widget.onDismissed?.call();
      });
    });
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double padH = scaleDimension(context, 10);
    final double padV = scaleDimension(context, 8);
    final double radius = scaleDimension(context, 8);
    return AnimatedOpacity(
      opacity: _opaque ? 1 : 0,
      duration: _fade,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(radius),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
          child: Text(
            widget.text,
            style: widget.textStyle ?? const TextStyle(color: Colors.white70),
          ),
        ),
      ),
    );
  }
}
