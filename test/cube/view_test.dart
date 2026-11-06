import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/cube/math3d.dart';
import 'package:rotathree/cube/painter.dart';
import 'package:rotathree/cube/rules.dart';
import 'package:rotathree/cube/view.dart';

void settle(CubeView view, {bool play = false}) {
  for (var i = 0; i < 60; i++) {
    view.frame(1 / 60, play);
  }
}

/// Where the glass on top of the game is drawn.
V3 drawnUp(CubeView view) => V3.ofVec(normalOf(view.game.down)).applyQuaternion(view.hubQ);

void main() {
  test('a turn of the cross steers the glass that comes on top, and draws it there', () {
    final game = CubeGame(const CubeConfig(seed: 3, inactiveFalls: false));
    final view = CubeView(game)..resize(400, 800);
    // ← (−1) brings the glass on the left to the top, as in the flat game.
    view.turnCross(-1);
    settle(view);
    expect(game.down, sides.indexWhere((s) => s.axis == 0 && s.sign == -1));
    for (final q in [1, 1, -1]) {
      view.turnCross(q);
      settle(view);
      expect(game.active, game.down);
      expect(drawnUp(view).y, closeTo(1, 1e-9));
      expect(view.placeOf(game.down), 'top');
    }
  });

  test('a tip shows itself while held, then brings the glass behind over the top', () {
    final game = CubeGame(const CubeConfig(seed: 5, inactiveFalls: false));
    final view = CubeView(game)..resize(400, 800);
    final back = sides.indexWhere((s) => s.axis == 2 && s.sign == -1);
    view.startTip(true);
    settle(view);
    expect(view.tipPreview, isNotNull);
    expect(game.down, isNot(back));
    expect(view.commitTip(true), isTrue);
    settle(view);
    expect(game.down, back);
    expect(view.placeOf(back), 'top');
    expect(view.tilting, isFalse);
  });

  test('the landing place fades out as a tip begins and back in after it', () {
    final game = CubeGame(const CubeConfig(seed: 5, inactiveFalls: false));
    final view = CubeView(game)..resize(400, 800);
    settle(view, play: true);
    expect(view.ghostShown, 1);
    view.startTip(true);
    view.commitTip(true);
    final seen = <double>[];
    for (var i = 0; i < 90; i++) {
      view.frame(1 / 60, true);
      seen.add(view.ghostShown);
    }
    // Gone while the hub leans over, then back by steps, not at once.
    expect(seen.reduce((a, b) => a < b ? a : b), 0);
    final back = seen.lastIndexOf(0) + 1;
    expect(seen[back], lessThan(0.2));
    expect(seen.last, greaterThan(0.95));
  });

  test('looking into the volume opens the picture into perspective and back', () {
    final view = CubeView(CubeGame(const CubeConfig(seed: 6)))..resize(400, 800);
    view.peeking = true;
    settle(view);
    expect(view.opened, greaterThan(0.95));
    expect(view.hubLines, isNotEmpty);
    view.peeking = false;
    settle(view);
    expect(view.opened, lessThan(0.01));
  });

  testWidgets('the painter draws a game, flat, mid-tip and open, without a fault', (tester) async {
    final game = CubeGame(const CubeConfig(seed: 7, centre: 10, arm: 9));
    final view = CubeView(game)..resize(390, 700);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final painter = CubePainter(view);
    for (var i = 0; i < 40; i++) {
      game.dropActive();
      view.frame(0.05, true);
    }
    settle(view, play: true);
    expect(view.solids, isNotEmpty);
    painter.paint(canvas, const Size(390, 700));
    view.startTip(false);
    for (var i = 0; i < 20; i++) {
      view.frame(1 / 60, true);
    }
    painter.paint(canvas, const Size(390, 700));
    view
      ..commitTip(false)
      ..peeking = true;
    settle(view, play: true);
    painter.paint(canvas, const Size(390, 700));
    recorder.endRecording().dispose();
  });
}
