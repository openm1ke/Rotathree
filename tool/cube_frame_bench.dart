// Measures how long frames of Cube take to build and to raster.
//
//   flutter run --profile -t tool/cube_frame_bench.dart
//
// It draws a game of Cube on a 10-wide cube with its arms filled up, as
// late in a game, and plays five scenes for a few seconds each: standing,
// turning the cross without pause, tipping the cube over, looking into its
// volume, and standing with the glasses' numbers shown. Then it prints the
// average and the 90th percentile of the build (UI thread) and raster times
// of each, how much of a frame went to stepping the view and to painting
// it, and quits.
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:rotathree/cube/painter.dart';
import 'package:rotathree/cube/rules.dart';
import 'package:rotathree/cube/view.dart';
import 'package:rotathree/ui/style.dart';

const _sceneSeconds = 6;
final _timings = <FrameTiming>[];
final _game = CubeGame(const CubeConfig(seed: 7, centre: 10, arm: 9, numberOfColors: 6, inactiveFalls: false));
final _view = CubeView(_game);

/// Time spent stepping the view, and drawing it, in the scene now measured.
final _stepping = Stopwatch(), _drawing = Stopwatch();
var _steps = 0, _draws = 0;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SchedulerBinding.instance.addTimingsCallback(_timings.addAll);
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, scaffoldBackgroundColor: Palette.bg),
      home: const _Stage(),
    ),
  );
  unawaited(_run());
}

/// The view, stepped and drawn every frame, as Cube's screen does.
class _Stage extends StatefulWidget {
  const _Stage();

  @override
  State<_Stage> createState() => _StageState();
}

class _StageState extends State<_Stage> with SingleTickerProviderStateMixin {
  final _repaint = ValueNotifier(0);
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      final seconds = (elapsed - _last).inMicroseconds / 1e6;
      _last = elapsed;
      _stepping.start();
      _view.frame(seconds.clamp(0, 0.1).toDouble(), true);
      _stepping.stop();
      _steps++;
      _repaint.value++;
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      _view.resize(box.maxWidth, box.maxHeight);
      return CustomPaint(painter: _Timed(CubePainter(_view), repaint: _repaint), size: Size.infinite);
    },
  );
}

/// The painter, timed.
class _Timed extends CustomPainter {
  _Timed(this.inner, {super.repaint});

  final CubePainter inner;

  @override
  void paint(Canvas canvas, Size size) {
    _drawing.start();
    inner.paint(canvas, size);
    _drawing.stop();
    _draws++;
  }

  @override
  bool shouldRepaint(_Timed old) => true;
}

Future<void> _run() async {
  await Future<void>.delayed(const Duration(seconds: 2));
  // Steps far apart: the sticks stay where they are dropped.
  for (var i = 0; i < 400 && !_game.isGameOver; i++) {
    _game.dropActive();
    _game.update(0.05);
    if (i % 25 == 24) _view.turnCross(1);
  }
  final view = PlatformDispatcher.instance.views.first;
  print(
    'cube_frame_bench: ${view.physicalSize.width.round()}x${view.physicalSize.height.round()} px, '
    'ratio ${view.devicePixelRatio}, ${view.display.refreshRate.round()} Hz, '
    '${_view.solids.length} blocks drawn, game over: ${_game.isGameOver}',
  );

  await _scene('still', () async {});
  await _scene('turning', () async {
    final turner = Timer.periodic(const Duration(milliseconds: 400), (_) => _view.turnCross(1));
    await Future<void>.delayed(const Duration(seconds: _sceneSeconds));
    turner.cancel();
  });
  await _scene('tipping', () async {
    var up = true;
    final tipper = Timer.periodic(const Duration(milliseconds: 900), (_) {
      _view.startTip(up);
      Timer(const Duration(milliseconds: 300), () => _view.commitTip(up));
      up = !up;
    });
    await Future<void>.delayed(const Duration(seconds: _sceneSeconds));
    tipper.cancel();
  });
  _view.peeking = true;
  await _scene('looking', () async {});
  _view
    ..peeking = false
    ..look = const CubeLook(numbers: true);
  await _scene('numbered', () async {});
  exit(0);
}

Future<void> _scene(String name, Future<void> Function() play) async {
  await Future<void>.delayed(const Duration(milliseconds: 500));
  _timings.clear();
  _stepping.reset();
  _drawing.reset();
  _steps = _draws = 0;
  final started = DateTime.now();
  await play();
  final rest = const Duration(seconds: _sceneSeconds) - DateTime.now().difference(started);
  if (rest > Duration.zero) await Future<void>.delayed(rest);
  await Future<void>.delayed(const Duration(milliseconds: 1200));
  final frames = List.of(_timings);
  if (frames.isEmpty) {
    print('cube_frame_bench: $name — no frames');
    return;
  }
  String line(String label, Duration Function(FrameTiming) of) {
    final ms = [for (final frame in frames) of(frame).inMicroseconds / 1000]..sort();
    final mean = ms.reduce((a, b) => a + b) / ms.length;
    final p90 = ms[(ms.length * 0.9).floor().clamp(0, ms.length - 1)];
    return '$label ${mean.toStringAsFixed(2)} ms (p90 ${p90.toStringAsFixed(2)})';
  }

  print(
    'cube_frame_bench: $name — ${frames.length} frames, '
    '${line('build', (f) => f.buildDuration)}, ${line('raster', (f) => f.rasterDuration)}; '
    'step ${(_stepping.elapsedMicroseconds / 1000 / _steps).toStringAsFixed(2)} ms, '
    'paint ${(_drawing.elapsedMicroseconds / 1000 / _draws).toStringAsFixed(2)} ms',
  );
}
