import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/game/config/game_config.dart';
import 'package:rotathree/game/engine/game_engine.dart';
import 'package:rotathree/game/engine/match_detector.dart';
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
