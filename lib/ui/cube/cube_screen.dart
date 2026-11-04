import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../cube/painter.dart';
import '../../cube/rules.dart';
import '../../cube/view.dart';
import '../audio/sound_effects.dart';
import '../i18n/strings.dart';
import '../style.dart';

/// Longest frame the game will simulate in one go (hitches, app switches).
const _maxFrameSeconds = 0.05;

/// A game of Cube: the picture (view.dart, painter.dart) and the keys of the
/// web's Cube: A D move, W turns the stick, Space drops, S speeds it up, ← →
/// (Q E) turn the cross, ↑ ↓ tip the hidden glasses over the top (held: shown
/// first), Z C steer the glass in front or behind, V held looks into the
/// volume.
class CubeScreen extends StatefulWidget {
  const CubeScreen({super.key, required this.onExit, this.config = const CubeConfig(centre: 10, arm: 9)});

  final VoidCallback onExit;
  final CubeConfig config;

  @override
  State<CubeScreen> createState() => CubeScreenState();
}

class CubeScreenState extends State<CubeScreen> with SingleTickerProviderStateMixin {
  late CubeGame game = CubeGame(widget.config);
  late final CubeView view = CubeView(game);
  late final Ticker _ticker = createTicker(_onTick);
  final _repaint = ValueNotifier<int>(0);
  final _focus = FocusNode();
  Duration _last = Duration.zero;
  int _score = 0;

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _focus.dispose();
    _repaint.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final frameMs = (elapsed - _last).inMicroseconds / 1000;
    _last = elapsed;
    final seconds = math.min(_maxFrameSeconds, math.max(0.0, frameMs / 1000));
    view.frame(seconds, !game.isGameOver);
    _repaint.value++;
    if (game.score != _score) setState(() => _score = game.score);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    final down = event is KeyDownEvent;
    final up = event is KeyUpEvent;
    if (!down && !up && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    bool handled = true;
    if (down || event is KeyRepeatEvent) {
      if (key == LogicalKeyboardKey.keyA) {
        view.move(-1);
      } else if (key == LogicalKeyboardKey.keyD) {
        view.move(1);
      } else if (key == LogicalKeyboardKey.keyW) {
        view.rotate(true);
      } else if (down && key == LogicalKeyboardKey.space) {
        view.drop();
      } else if (down && key == LogicalKeyboardKey.keyS) {
        view.softDrop(true);
      } else if (down && (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.keyQ)) {
        // As in the flat game: ← clockwise, the glass on the left coming to
        // the top; → counterclockwise.
        view.turnCross(-1);
      } else if (down && (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.keyE)) {
        view.turnCross(1);
      } else if (down && key == LogicalKeyboardKey.arrowUp) {
        view.startTip(true);
      } else if (down && key == LogicalKeyboardKey.arrowDown) {
        view.startTip(false);
      } else if (down && key == LogicalKeyboardKey.keyZ) {
        view.steer('front');
      } else if (down && key == LogicalKeyboardKey.keyC) {
        view.steer('back');
      } else if (down && key == LogicalKeyboardKey.keyV) {
        view.peeking = true;
      } else {
        handled = false;
      }
    } else {
      if (key == LogicalKeyboardKey.keyS) {
        view.softDrop(false);
      } else if (key == LogicalKeyboardKey.arrowUp) {
        view.commitTip(true);
      } else if (key == LogicalKeyboardKey.arrowDown) {
        view.commitTip(false);
      } else if (key == LogicalKeyboardKey.keyV) {
        view.peeking = false;
      } else {
        handled = false;
      }
    }
    return handled ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: context.tr('Назад'),
                    onPressed: clicking(widget.onExit),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Palette.text),
                  ),
                  const Spacer(),
                  Text('$_score', key: const ValueKey('cube-score'), style: Type.display(26)),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  view.resize(box.maxWidth, box.maxHeight);
                  return CustomPaint(size: box.biggest, painter: CubePainter(view, repaint: _repaint));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
