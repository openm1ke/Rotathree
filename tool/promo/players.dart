// Players for the promo: each looks for the best place for the stick by
// playing every place out on a copy of the game, and gives the real game the
// inputs to get there, one at a time, as a hand would.
import 'dart:math';

import 'package:rotathree/cube/rules.dart';
import 'package:rotathree/game/engine/game_engine.dart';
import 'package:rotathree/game/engine/rotation_transform.dart';
import 'package:rotathree/game/model/side.dart';
import 'package:rotathree/game/state/game_state.dart';

/// Inputs for the real game, given one per call of [step].
class Plan {
  Plan(this._inputs, this.points);

  final List<void Function()> _inputs;

  /// What the copy scored with it.
  final int points;

  bool get done => _inputs.isEmpty;

  void step() {
    if (_inputs.isNotEmpty) _inputs.removeAt(0)();
  }
}

class CubePlayer {
  CubePlayer(this.game, {int seed = 1}) : _random = Random(seed);

  final CubeGame game;
  final Random _random;

  static Vec _unit(int axis, [int sign = 1]) => Vec(axis == 0 ? sign : 0, axis == 1 ? sign : 0, axis == 2 ? sign : 0);

  /// The best place for the active stick, or null while the game is not at
  /// rest between moves.
  Plan? plan() {
    final snapshot = game.snapshot();
    final piece = game.activePiece;
    if (snapshot == null || piece == null) return null;
    final (a, b) = game.hub.crossAxes(game.active);
    final n = sides[game.active].axis;
    final turns = <List<Vec>>[
      [],
      [_unit(a)],
      [_unit(b)],
      [_unit(n)],
      [_unit(a), _unit(a)],
      [_unit(b), _unit(b)],
      [_unit(n), _unit(n)],
      [_unit(a), _unit(n)],
      [_unit(b), _unit(n)],
    ];
    final tried = <String>{};
    List<Vec>? bestTurns;
    var bestMoves = <Vec>[];
    var bestValue = double.negativeInfinity;
    var bestPoints = 0;
    for (final turn in turns) {
      for (var da = -7; da <= 7; da++) {
        for (var db = -7; db <= 7; db++) {
          final copy = CubeGame.restore(snapshot);
          for (final axis in turn) {
            copy.rotate(axis);
          }
          final moves = [
            for (var i = 0; i < da.abs(); i++) _unit(a, da.sign),
            for (var i = 0; i < db.abs(); i++) _unit(b, db.sign),
          ];
          for (final move in moves) {
            copy.move(move);
          }
          final stick = copy.activePiece;
          if (stick == null || !tried.add('${stick.pivot}|${stick.dir}|${stick.colors}')) continue;
          final before = copy.score;
          copy.dropActive();
          for (var i = 0; i < 400; i++) {
            copy.update(0.05);
            if (copy.phase == CubePhase.playing && i > 2) break;
          }
          final points = copy.score - before;
          final value = copy.isGameOver ? -1e9 : points * 10.0 + _random.nextDouble();
          if (value > bestValue) {
            bestValue = value;
            bestTurns = turn;
            bestMoves = moves;
            bestPoints = points;
          }
        }
      }
    }
    if (bestTurns == null) return null;
    return Plan([
      for (final axis in bestTurns) () => game.rotate(axis),
      for (final move in bestMoves) () => game.move(move),
      game.dropActive,
    ], bestPoints);
  }
}

class FlatPlayer {
  FlatPlayer(this.engine, {int seed = 1}) : _random = Random(seed);

  final GameEngine engine;
  final Random _random;

  /// How high the stack of [side] stands, in cells from its floor.
  static int _height(GameEngine engine, Side side) {
    final glass = GlassView(engine.board, side);
    for (var row = 0; row < glass.depth; row++) {
      for (var lane = 0; lane < glass.lanes; lane++) {
        if (glass.at(row, lane) != null) return glass.depth - row;
      }
    }
    return 0;
  }

  /// The best glass to bring on top and place for its stick, or null while
  /// the game is not at rest between moves. Low stacks are kept low, so that
  /// every glass fills and the game goes on.
  Plan? plan() {
    if (engine.phase != GamePhase.playing || engine.activePiece == null) return null;
    final snapshot = engine.snapshot();
    final current = engine.activeSide;
    var bestValue = double.negativeInfinity;
    var bestSide = current;
    var bestTurns = 0, bestShift = 0, bestPoints = 0;
    for (final side in engine.sides) {
      for (var turns = 0; turns < 4; turns++) {
        for (var shift = -10; shift <= 10; shift++) {
          final copy = GameEngine(config: engine.config)..restoreSnapshot(snapshot);
          if (side != current) copy.activateSide(side);
          if (copy.activeSide != side || copy.activePiece == null) continue;
          for (var i = 0; i < turns; i++) {
            copy.rotateActive();
          }
          for (var i = 0; i < shift.abs(); i++) {
            copy.moveActive(shift.sign);
          }
          final before = copy.state.score;
          copy.dropActive();
          for (var i = 0; i < 400; i++) {
            copy.update(0.05);
            if (copy.phase == GamePhase.playing && i > 2) break;
          }
          final points = copy.state.score - before;
          final value = copy.isGameOver
              ? -1e9
              : points * 10.0 - _height(copy, side) * 0.8 - (side == current ? 0 : 0.6) + _random.nextDouble() * 0.5;
          if (value > bestValue) {
            bestValue = value;
            bestSide = side;
            bestTurns = turns;
            bestShift = shift;
            bestPoints = points;
          }
        }
      }
    }
    return Plan([
      if (bestSide != current) () => engine.activateSide(bestSide),
      for (var i = 0; i < bestTurns; i++) engine.rotateActive,
      for (var i = 0; i < bestShift.abs(); i++) () => engine.moveActive(bestShift.sign),
      engine.dropActive,
    ], bestPoints);
  }
}
