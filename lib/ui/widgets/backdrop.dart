import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../style.dart';

/// Soft glows over a faint grid, with the web menu's drifting squares.
///
/// The squares fall in a layer of their own and move with every frame the
/// screen shows. The glows and grid drift so slowly that ten updates a second
/// look smooth, so their layer repaints less often.
class Backdrop extends StatefulWidget {
  const Backdrop({super.key, this.menu = false, this.paused = false, this.animated = true});
  final bool menu, paused, animated;

  @override
  State<Backdrop> createState() => _BackdropState();
}

class _BackdropState extends State<Backdrop> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  /// Seconds since the animation started; drives the glows and grid.
  final ValueNotifier<double> _time = ValueNotifier(0);

  /// Seconds since the animation started; drives the falling squares.
  final ValueNotifier<double> _squareTime = ValueNotifier(0);
  final Stopwatch _clock = Stopwatch();
  Timer? _timer;
  late final Ticker _ticker = createTicker((_) => _squareTime.value = _clock.elapsedMicroseconds / 1e6);
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
    if (widget.menu != oldWidget.menu || widget.paused != oldWidget.paused || widget.animated != oldWidget.animated) {
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
    _timer = null;
    _ticker.stop();
    if (!widget.animated || _reduceMotion || !_visible || !_active || widget.paused) {
      _clock.stop();
      return;
    }
    _clock.start();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _time.value = _clock.elapsedMilliseconds / 1000;
    });
    if (widget.menu) _ticker.start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ticker.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _time.dispose();
    _squareTime.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: CustomPaint(painter: _BackdropPainter(_time), size: Size.infinite),
        ),
        if (widget.menu)
          RepaintBoundary(
            child: CustomPaint(painter: _SquaresPainter(_squareTime), size: Size.infinite),
          ),
      ],
    );
  }
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter(this.time) : super(repaint: time);

  final ValueListenable<double> time;

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
  }

  @override
  bool shouldRepaint(_BackdropPainter oldDelegate) => false;
}

/// The squares of the web menu, falling behind the screen content.
class _SquaresPainter extends CustomPainter {
  _SquaresPainter(this.time) : super(repaint: time);

  final ValueListenable<double> time;
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
    canvas.save();
    canvas.clipRect(Offset.zero & size);
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

  @override
  bool shouldRepaint(_SquaresPainter oldDelegate) => false;
}
