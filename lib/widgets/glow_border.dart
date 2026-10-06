import 'dart:math' as math;

import 'package:flutter/material.dart';

class GlowBorder extends StatefulWidget {
  const GlowBorder({
    super.key,
    required this.child,
    this.color = const Color(0xFF1E3A8A),
    this.radius = 10,
    this.width = 2,
  });

  final Widget child;
  final Color color;
  final double radius;
  final double width;

  @override
  State<GlowBorder> createState() => _GlowBorderState();
}

class _GlowBorderState extends State<GlowBorder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2600))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        return CustomPaint(
          foregroundPainter: _GlowPainter(_c.value * 2 * math.pi,
              widget.color, widget.radius, widget.width),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _GlowPainter extends CustomPainter {
  _GlowPainter(this.angle, this.color, this.radius, this.width);

  final double angle;
  final Color color;
  final double radius;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
        rect.deflate(width / 2), Radius.circular(radius));

    // calm base border
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = color.withValues(alpha: 0.25),
    );

    // the moving bright segment, blurred so it glows
    final shader = SweepGradient(
      colors: [
        color.withValues(alpha: 0),
        color,
        Colors.white.withValues(alpha: 0.9),
        color,
        color.withValues(alpha: 0),
      ],
      stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
      transform: GradientRotation(angle),
    ).createShader(rect);

    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width * 2
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5)
        ..shader = shader,
    );
  }

  @override
  bool shouldRepaint(_GlowPainter old) => old.angle != angle;
}
