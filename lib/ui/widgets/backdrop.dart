import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../style.dart';

/// The background of every screen: two soft glows drifting slowly over a
/// faint grid that fades towards the edges.
class Backdrop extends StatefulWidget {
  const Backdrop({super.key});

  @override
  State<Backdrop> createState() => _BackdropState();
}

class _BackdropState extends State<Backdrop> with SingleTickerProviderStateMixin {
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 40),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _BackdropPainter(CurvedAnimation(parent: _drift, curve: Curves.easeInOut)),
        size: Size.infinite,
      ),
    );
  }
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter(this.drift) : super(repaint: drift);

  final Animation<double> drift;

  @override
  void paint(Canvas canvas, Size size) {
    final area = Offset.zero & size;
    canvas.drawRect(area, Paint()..color = Palette.bg);

    final reach = math.max(size.width, size.height);
    final t = drift.value;
    void glow(Offset centre, Color color, double radius) {
      canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [color.withValues(alpha: 0.2), color.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: centre, radius: radius)),
      );
    }

    glow(
      Offset(size.width * (0.05 + 0.3 * t), size.height * (0.02 + 0.16 * t)),
      Palette.violet,
      reach * (0.62 + 0.08 * t),
    );
    glow(
      Offset(size.width * (0.98 - 0.28 * t), size.height * (0.98 - 0.14 * t)),
      Palette.accentStrong,
      reach * (0.6 + 0.06 * t),
    );

    // A grid that is only visible around the middle of the screen.
    const step = 34.0;
    final lines = Path();
    for (var x = size.width / 2 % step; x < size.width; x += step) {
      lines
        ..moveTo(x, 0)
        ..lineTo(x, size.height);
    }
    for (var y = size.height / 2 % step; y < size.height; y += step) {
      lines
        ..moveTo(0, y)
        ..lineTo(size.width, y);
    }
    canvas.drawPath(
      lines,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = RadialGradient(
          colors: [Colors.white.withValues(alpha: 0.035), Colors.white.withValues(alpha: 0)],
          stops: const [0, 0.78],
        ).createShader(Rect.fromCircle(center: area.center, radius: reach * 0.62)),
    );
  }

  @override
  bool shouldRepaint(_BackdropPainter oldDelegate) => false;
}
