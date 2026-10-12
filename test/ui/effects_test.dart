import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/game/config/game_config.dart';
import 'package:rotathree/game/engine/game_engine.dart';
import 'package:rotathree/game/engine/game_event.dart';
import 'package:rotathree/game/engine/match_detector.dart';
import 'package:rotathree/game/engine/placement_engine.dart';
import 'package:rotathree/game/model/color.dart';
import 'package:rotathree/game/model/position.dart';
import 'package:rotathree/game/state/game_state.dart';
import 'package:rotathree/ui/data/settings.dart';
import 'package:rotathree/ui/field/effects.dart';

/// A line of [length] red cells across row [row] of the centre.
MatchResult lineOf(int length, {int row = 15}) {
  final cells = [for (var i = 0; i < length; i++) CellPosition(row, 6 + i)];
  return MatchResult(
    [MatchRun(color: BlockColor.red, cells: cells, isHorizontal: true)],
    cells.toSet(),
  );
}

/// Pops [lines] at once, as the engine does in its clearing phase, and lets
/// the effects react to it once.
Effects popping(List<MatchResult> lines, {required ExplosionStyle style}) {
  final engine = GameEngine(config: const GameConfig(glassCount: 1, seed: 5));
  final fx = Effects()..explosion = style;
  fx.reset(engine.activeSide);
  for (final line in lines) {
    for (final cell in line.cells) {
      engine.board.set(cell.row, cell.col, BlockColor.red);
    }
  }
  engine.state
    ..activeMatch = MatchResult(
      [for (final line in lines) ...line.runs],
      {for (final line in lines) ...line.cells},
    )
    ..phase = GamePhase.clearing;
  fx.update(0.001, engine);
  return fx;
}

void main() {
  test('recoil stays in view and settles during sustained 20 FPS frames', () {
    final engine = GameEngine(config: const GameConfig(glassCount: 1, seed: 5));
    final fx = Effects()..reset(engine.activeSide);
    fx.consume([PieceMoved(engine.activeSide, direction: 1, blocked: true)], engine);
    for (var frame = 0; frame < 200; frame++) {
      fx.update(0.05, engine);
      expect(fx.kickX.isFinite, isTrue);
      expect(fx.kickX.abs(), lessThan(0.5), reason: 'frame $frame');
    }
    expect(fx.kickX, 0);
    expect(fx.kickY, 0);
    expect(fx.settled, isTrue);
  });

  test('repeated drops and combos stay bounded through slow and irregular frames', () {
    final engine = GameEngine(config: const GameConfig(glassCount: 1, seed: 5));
    final fx = Effects()..reset(engine.activeSide);
    final piece = engine.activePiece!;
    final placement = const PlacementEngine().computeDrop(engine.board, piece.side, piece.piece, piece.column)!;
    const frames = [0.05, 0.05, 1 / 60, 0.033, 0.25, 0.05];
    for (var frame = 0; frame < 300; frame++) {
      if (frame % 12 == 0) {
        fx.consume([
          PieceMoved(engine.activeSide, direction: 1, blocked: true),
          PieceLanded(placement, dropped: true),
          MatchScored(combo: 6, score: 600, match: lineOf(6)),
        ], engine);
      }
      fx.update(frames[frame % frames.length], engine);
      expect((fx.kickX + fx.shakeX).abs(), lessThan(1));
      expect((fx.kickY + fx.shakeY).abs(), lessThan(1));
      expect(fx.punch, inInclusiveRange(0, 0.06));
    }
    for (var frame = 0; frame < 60; frame++) {
      fx.update(0.05, engine);
    }
    expect(fx.settled, isTrue);
  });

  test('recoil follows elapsed time regardless of frame rate and freezes at zero delta', () {
    final engine = GameEngine(config: const GameConfig(glassCount: 1, seed: 5));
    final slow = Effects()..reset(engine.activeSide);
    final fast = Effects()..reset(engine.activeSide);
    final events = [PieceMoved(engine.activeSide, direction: 1, blocked: true)];
    slow.consume(events, engine);
    fast.consume(events, engine);
    slow.update(0.2, engine);
    for (var frame = 0; frame < 12; frame++) {
      fast.update(1 / 60, engine);
    }
    expect(slow.kickX, isNot(0));
    expect(slow.kickX, closeTo(fast.kickX, 1e-9));
    final before = slow.kickX;
    slow.update(0, engine);
    expect(slow.kickX, before);
  });

  test('off skips bursts and clears existing decorative effects immediately', () {
    final off = popping([lineOf(6)], style: ExplosionStyle.off);
    expect(off.particles, isEmpty);
    expect(off.rings, isEmpty);
    expect(off.flashes, isEmpty);
    expect(off.veils, isEmpty);
    final active = popping([lineOf(6)], style: ExplosionStyle.varied);
    expect(active.particles, isNotEmpty);
    active.explosion = ExplosionStyle.off;
    expect(active.particles, isEmpty);
    expect(active.rings, isEmpty);
    expect(active.flashes, isEmpty);
    expect(active.veils, isEmpty);
  });

  test('large simultaneous clears have a bounded particle budget', () {
    final fx = popping([for (var row = 9; row < 19; row++) lineOf(10, row: row)], style: ExplosionStyle.varied);
    expect(fx.particles.length, Effects.maxParticles);
  });

  test('unified explosions are the same whatever the line', () {
    final short = popping([lineOf(3)], style: ExplosionStyle.unified);
    final long = popping([lineOf(6)], style: ExplosionStyle.unified);
    expect(short.particles.length, 3 * 9);
    expect(long.particles.length, 6 * 9);
    expect(long.flashes, isEmpty);
    expect(long.veils, isEmpty);
  });

  test('varied explosions grow with the length of the line', () {
    final six = popping([lineOf(6)], style: ExplosionStyle.varied);
    // Six cells, thirty shards each, and a golden bar over the line.
    expect(six.particles.length, 6 * 30);
    expect(six.flashes.single.life, closeTo(0.3, 1e-9));
    expect(six.flashes.single.color, const Color(0xFFFFD76A));
  });

  test('three lines at once also wash the whole field', () {
    final fx = popping(
      [lineOf(3, row: 12), lineOf(3, row: 13), lineOf(3, row: 14)],
      style: ExplosionStyle.varied,
    );
    expect(fx.veils.length, 1);
    // Each line after the first sends a wave out of its middle.
    expect(fx.rings.where((ring) => ring.reach == 2.6).length, 2);
  });
}
