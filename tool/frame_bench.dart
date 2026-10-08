// Measures how long frames of the game take to build and to raster.
//
//   flutter run --profile -t tool/frame_bench.dart
//
// It opens the game screen on a busy four-glass board and plays three
// scenes for a few seconds each — standing still, turning without pause, and
// one explosion after another — then prints the average and the 90th
// percentile of the build (UI thread) and raster times of each, and quits.
// Debug builds work too, but only their raster times mean anything.
// ignore_for_file: avoid_print, invalid_use_of_visible_for_testing_member

import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:rotathree/game/config/modes.dart';
import 'package:rotathree/game/engine/rotation_transform.dart';
import 'package:rotathree/game/model/color.dart';
import 'package:rotathree/game/session.dart';
import 'package:rotathree/game/state/game_state.dart';
import 'package:rotathree/ui/data/progress.dart';
import 'package:rotathree/ui/data/settings.dart';
import 'package:rotathree/ui/game/game_screen.dart';
import 'package:rotathree/ui/style.dart';
import 'package:rotathree/ui/widgets/backdrop.dart';

const _sceneSeconds = 6;

final _game = GlobalKey<GameScreenState>();
final _timings = <FrameTiming>[];

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SchedulerBinding.instance.addTimingsCallback(_timings.addAll);
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, scaffoldBackgroundColor: Palette.bg),
      home: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            const Positioned.fill(child: Backdrop()),
            Positioned.fill(
              child: GameScreen(
                key: _game,
                session: const CustomSession(defaultCustom),
                settings: Settings.defaults(),
                progress: Progress.initial(),
                blocked: false,
                onSettings: () {},
                onExit: () {},
                onLevels: () {},
                onRetry: (_) {},
                onInsane: () {},
                onCustomise: () {},
                onRecord: (_) {},
                onProgress: (_) {},
              ),
            ),
          ],
        ),
      ),
    ),
  );
  unawaited(_run());
}

Future<void> _run() async {
  await Future<void>.delayed(const Duration(seconds: 2));
  final engine = _game.currentState!.engine;
  final board = engine.board;

  // A full centre and five rows of every arm, in a pattern with no line of
  // three, and pieces that never fall on their own: a still, busy picture.
  const colours = [BlockColor.red, BlockColor.blue, BlockColor.yellow];
  final arm = board.arm;
  final last = arm + board.center - 1;
  for (var row = 0; row < board.size; row++) {
    for (var col = 0; col < board.size; col++) {
      if (!board.isInside(row, col)) continue;
      final away = [arm - row, row - last, arm - col, col - last].reduce((a, b) => a > b ? a : b);
      if (board.isCenter(row, col) || away <= 5) board.set(row, col, colours[(col + 2 * row) % 3]);
    }
  }
  engine.setSteps(1e6, 1e6);

  final view = PlatformDispatcher.instance.views.first;
  print(
    'frame_bench: ${view.physicalSize.width.round()}x${view.physicalSize.height.round()} px, '
    'ratio ${view.devicePixelRatio}, ${view.display.refreshRate.round()} Hz, '
    '${board.blockCount} blocks',
  );

  await _scene('still', () async {});

  await _scene('turning', () async {
    final turner = Timer.periodic(const Duration(milliseconds: 300), (_) => engine.switchSide(1));
    await Future<void>.delayed(const Duration(seconds: _sceneSeconds));
    turner.cancel();
  });
  await Future<void>.delayed(const Duration(seconds: 1));

  await _scene('explosions', () async {
    // A line of six just above the pile of the active glass, then a drop:
    // the line pops, the piece falls into its place, and it starts again.
    final popper = Timer.periodic(const Duration(milliseconds: 700), (_) {
      if (engine.phase != GamePhase.playing) return;
      final glass = GlassView(board, engine.activeSide);
      for (var lane = 0; lane < 6; lane++) {
        glass.set(3, lane, BlockColor.blue);
      }
      engine.dropActive();
    });
    await Future<void>.delayed(const Duration(seconds: _sceneSeconds));
    popper.cancel();
  });

  exit(0);
}

/// Plays [play] (or waits, when it returns at once) and reports the frames
/// drawn meanwhile.
Future<void> _scene(String name, Future<void> Function() play) async {
  await Future<void>.delayed(const Duration(milliseconds: 500));
  _timings.clear();
  final started = DateTime.now();
  await play();
  final rest = const Duration(seconds: _sceneSeconds) - DateTime.now().difference(started);
  if (rest > Duration.zero) await Future<void>.delayed(rest);
  // Timings are delivered in batches, about a second behind.
  await Future<void>.delayed(const Duration(milliseconds: 1200));
  final frames = List.of(_timings);
  if (frames.isEmpty) {
    print('frame_bench: $name — no frames');
    return;
  }
  String line(String label, Duration Function(FrameTiming) of) {
    final ms = [for (final frame in frames) of(frame).inMicroseconds / 1000]..sort();
    final mean = ms.reduce((a, b) => a + b) / ms.length;
    final p90 = ms[(ms.length * 0.9).floor().clamp(0, ms.length - 1)];
    return '$label ${mean.toStringAsFixed(2)} ms (p90 ${p90.toStringAsFixed(2)})';
  }

  print(
    'frame_bench: $name — ${frames.length} frames, '
    '${line('build', (f) => f.buildDuration)}, ${line('raster', (f) => f.rasterDuration)}',
  );
}
