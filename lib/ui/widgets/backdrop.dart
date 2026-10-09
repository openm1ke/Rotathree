import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../style.dart';

/// Soft glows over a faint grid, with the web menu's drifting squares.
class Backdrop extends StatefulWidget {
  const Backdrop({super.key, this.menu = false, this.paused = false});
  final bool menu, paused;

  @override
  State<Backdrop> createState() => _BackdropState();
}

class _BackdropState extends State<Backdrop> with WidgetsBindingObserver {
  final ValueNotifier<double> _time = ValueNotifier(0);
  final Stopwatch _clock = Stopwatch();
  Timer? _timer;
  bool _reduceMotion = false, _visible = true, _active = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _visible = TickerMode.valuesOf(context).enabled;
    _syncAnimation();
  }

  @override
  void didUpdateWidget(Backdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.menu != oldWidget.menu || widget.paused != oldWidget.paused) {
      _syncAnimation();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    _syncAnimation();
  }

  void _syncAnimation() {
    _timer?.cancel();
    if (_reduceMotion || !_visible || !_active || widget.paused) {
      _clock.stop();
      return;
    }
    _clock.start();
    // Only this canvas repaints: 24 fps for squares, 10 for slow glows.
    _timer = Timer.periodic(Duration(milliseconds: widget.menu ? 42 : 100), (_) {
      _time.value = _clock.elapsedMilliseconds / 1000;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _BackdropPainter(_time, menu: widget.menu),
        size: Size.infinite,
      ),
    );
  }
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter(this.time, {required this.menu}) : super(repaint: time);

  final ValueListenable<double> time;
  final bool menu;
  static const _squares = <(double, double, double, int)>[
    (.06, 26, 0, 0),
    (.18, 16, 3.2, 1),
    (.31, 22, 6.1, 2),
    (.44, 14, 1.4, 3),
    (.57, 30, 4.7, 4),
    (.70, 18, 8.3, 5),
    (.83, 24, 2.6, 6),
    (.92, 14, 6.9, 7),
    (.12, 20, 9.5, 8),
    (.76, 34, .8, 0),
    (.50, 18, 11.2, 2),
    (.24, 28, 7.6, 4),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final area = Offset.zero & size;
    canvas.drawRect(area, Paint()..color = Palette.bg);

    final reach = math.max(size.width, size.height);
    final phase = (time.value / 40) % 2;
    final t = Curves.easeInOut.transform(phase <= 1 ? phase : 2 - phase);
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
    if (menu) {
      canvas.save();
      canvas.clipRect(area);
      final paint = Paint();
      for (final (x, edge, delay, colour) in _squares) {
        final fall = ((time.value + delay) / 26) % 1;
        canvas.save();
        canvas.translate(size.width * x + edge / 2, size.height * (-.3 + 1.5 * fall) + edge / 2);
        canvas.rotate(fall * math.pi * 160 / 180);
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(-edge / 2, -edge / 2, edge, edge), const Radius.circular(6)),
          paint..color = classicColours[colour].withValues(alpha: .16),
        );
        canvas.restore();
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_BackdropPainter oldDelegate) => oldDelegate.menu != menu;
}
