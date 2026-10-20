import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Premium monochrome backdrop: soft pools of light and shadow on a pearl gradient.
/// Sits above the Navigator so every screen shares it and the glass panels have something to frost.
class GlassBackground extends StatelessWidget {
  const GlassBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const CustomPaint(painter: _BackdropPainter()),
        child,
      ],
    );
  }
}

class _BackdropPainter extends CustomPainter {
  const _BackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          rect.topCenter,
          rect.bottomCenter,
          const [Color(0xFFF8F8F8), Color(0xFFE6E6E6)],
        ),
    );
    void pool(Offset c, double r, Color color) {
      canvas.drawCircle(c, r, Paint()..shader = ui.Gradient.radial(c, r, [color, color.withAlpha(0)]));
    }

    final w = size.width;
    final h = size.height;
    pool(Offset(w * 0.1, h * 0.08), w * 0.9, const Color(0xE6FFFFFF));
    pool(Offset(w * 0.95, h * 0.30), w * 0.75, const Color(0x80BEBEBE));
    pool(Offset(w * 0.05, h * 0.82), w * 0.95, const Color(0x73A9A9A9));
    pool(Offset(w * 0.85, h * 1.0), w * 0.6, const Color(0x668A8A8A));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Frosted glass card: backdrop blur, translucent white gradient, bright hairline edge.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.radius = 24,
    this.padding,
    this.blur = 20,
    this.dark = false,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final double blur;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: r,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: r,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: dark
                  ? const [Color(0x40FFFFFF), Color(0x1AFFFFFF)]
                  : const [Color(0xB3FFFFFF), Color(0x73FFFFFF)],
            ),
            border: Border.all(color: dark ? const Color(0x33FFFFFF) : const Color(0xCCFFFFFF)),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
          ),
        ),
      ),
    );
  }
}

/// Frosted bar pinned to the bottom edge (navigation).
class GlassBar extends StatelessWidget {
  const GlassBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: Color(0x99FFFFFF),
            border: Border(top: BorderSide(color: Color(0xCCFFFFFF))),
          ),
          child: SafeArea(top: false, child: child),
        ),
      ),
    );
  }
}

class GlassIconButton extends StatelessWidget {
  const GlassIconButton({super.key, required this.icon, required this.onPressed, this.tooltip});

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0x8CFFFFFF),
            border: Border.all(color: const Color(0xCCFFFFFF)),
          ),
          child: IconButton(onPressed: onPressed, icon: Icon(icon), tooltip: tooltip),
        ),
      ),
    );
  }
}

/// Dialog route that softly blurs everything behind it.
Future<T?> showGlassDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: 'Dismiss',
    barrierColor: const Color(0x26000000),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, anim, secondary) => Stack(
      fit: StackFit.expand,
      children: [
        BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: 7, sigmaY: 7), child: const SizedBox.expand()),
        builder(ctx),
      ],
    ),
    transitionBuilder: (ctx, anim, secondary, child) => FadeTransition(
      opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.96, end: 1).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: child,
      ),
    ),
  );
}

/// Bottom sheet made of frosted glass with its own grab handle.
Future<T?> showGlassSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: Colors.transparent,
    elevation: 0,
    showDragHandle: false,
    barrierColor: const Color(0x26000000),
    builder: (ctx) => ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 26, sigmaY: 26),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: Color(0xB8FFFFFF),
            border: Border(top: BorderSide(color: Color(0xE6FFFFFF))),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(color: const Color(0x4D000000), borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(height: 10),
                Flexible(child: builder(ctx)),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
