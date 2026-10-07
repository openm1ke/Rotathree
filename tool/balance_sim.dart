// Balance simulation for the prototype: lets bots of three skill levels play
// many seeded games per configuration and prints aggregate statistics.
//
//   dart run tool/balance_sim.dart [--games=40] [--cap=300] [--suite=all]
//                                  [--colours=3,4]
//                                  [--variant=<part of a row label>]
//
// Suites: speed (step intervals × colours), rules (arm length and rule
// variants), all.
// ignore_for_file: avoid_print

import 'dart:math' as math;

import 'package:rotathree/game/config/game_config.dart';
import 'package:rotathree/game/engine/game_engine.dart';
import 'package:rotathree/game/engine/game_event.dart';
import 'package:rotathree/game/engine/rotation_transform.dart';
import 'package:rotathree/game/model/side.dart';
import 'package:rotathree/game/sim/bot_player.dart';

const _tick = 1 / 60;

class GameStats {
  double seconds = 0;
  bool survived = false;
  int pieces = 0;
  int selfLocked = 0;
  int dropped = 0;
  int vertical = 0;
  int chains = 0;
  int cascades = 0;
  int bestCombo = 0;
  int score = 0;
  double fillSum = 0;
  double armFillSum = 0;
  int fillSamples = 0;
  int decisions = 0;
  int choseNonUrgent = 0;

  /// Screen slot of the glass that overflowed (top = the active one).
  Side? fatalSlot;
}

GameStats playOne(GameConfig config, BotProfile profile, int seed, double cap) {
  final engine = GameEngine(config: config.copyWith(seed: seed));
  final bot = BotPlayer(engine, profile: profile, random: math.Random(seed));
  final stats = GameStats();
  var nextSample = 1.0;

  while (!engine.isGameOver && engine.state.elapsedSeconds < cap) {
    bot.tick(_tick);
    engine.update(_tick);
    for (final event in engine.drainEvents()) {
      // Orientation only says something about pieces the bot placed itself.
      if (event is PieceLanded && event.dropped) {
        stats.dropped++;
        if (event.placement.piece.isVertical) stats.vertical++;
      }
      if (event is MatchScored) {
        if (event.combo == 1) stats.chains++;
        if (event.combo == 2) stats.cascades++;
      }
    }
    if (engine.state.elapsedSeconds >= nextSample) {
      nextSample += 1.0;
      final board = engine.board;
      var inArms = 0;
      for (final block in board.blocks) {
        if (!board.isCenter(block.position.row, block.position.col)) inArms++;
      }
      stats.fillSum += board.blockCount;
      stats.armFillSum += inArms;
      stats.fillSamples++;
    }
  }

  final state = engine.state;
  stats
    ..seconds = math.min(state.elapsedSeconds, cap)
    ..survived = !engine.isGameOver
    ..pieces = state.piecesPlaced
    ..selfLocked = state.selfLocked
    ..bestCombo = state.bestCombo
    ..score = state.score
    ..decisions = bot.decisions
    ..choseNonUrgent = bot.choseNonUrgent;
  final over = state.gameOver;
  if (over != null) {
    stats.fatalSlot = RotationTransform.slotOfSide(state.activeSide, over.side);
  }
  return stats;
}

double _median(List<double> values) {
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}

String _pad(Object value, int width) => value.toString().padLeft(width);
String _f(double value, [int digits = 1]) => value.toStringAsFixed(digits);

/// When set (`--variant=`), only rows whose label contains it are run.
String? onlyVariant;

void report(String label, GameConfig config, int games, double cap) {
  final only = onlyVariant;
  if (only != null && !label.contains(only)) return;
  for (final profile in BotProfile.all) {
    final runs = [
      for (var seed = 1; seed <= games; seed++)
        playOne(config, profile, seed, cap),
    ];
    int sum(int Function(GameStats) pick) =>
        runs.fold<int>(0, (total, run) => total + pick(run));

    final seconds = runs.map((r) => r.seconds).toList();
    final total = seconds.reduce((a, b) => a + b);
    final pieces = sum((r) => r.pieces);
    final chains = sum((r) => r.chains);
    final samples = math.max(1, sum((r) => r.fillSamples));
    final fill = runs.fold<double>(0, (s, r) => s + r.fillSum) / samples;
    final armFill = runs.fold<double>(0, (s, r) => s + r.armFillSum) / samples;
    final fatal = {
      for (final slot in Side.values)
        slot: runs.where((r) => r.fatalSlot == slot).length,
    };
    double percent(int part, int whole) => 100 * part / math.max(1, whole);

    print(
      '${label.padRight(24)} ${profile.name.padRight(8)}'
      ' med ${_pad(_f(_median(seconds), 0), 4)}s'
      ' mean ${_pad(_f(total / runs.length, 0), 4)}s'
      ' cap ${_pad(runs.where((r) => r.survived).length, 2)}/$games'
      ' | pcs/min ${_pad(_f(pieces / total * 60), 5)}'
      ' self ${_pad(_f(percent(sum((r) => r.selfLocked), pieces), 0), 3)}%'
      ' vert ${_pad(_f(percent(sum((r) => r.vertical), sum((r) => r.dropped)), 0), 3)}%'
      ' | match ${_pad(_f(percent(chains, pieces), 0), 3)}%'
      ' casc ${_pad(_f(percent(sum((r) => r.cascades), chains), 0), 3)}%'
      ' bestCombo ${_f(sum((r) => r.bestCombo) / runs.length)}'
      ' | fill ${_pad(_f(fill), 5)} arms ${_pad(_f(armFill), 4)}'
      ' | pts/min ${_pad(_f(sum((r) => r.score) / total * 60, 0), 5)}'
      ' | free-choice ${_pad(_f(percent(sum((r) => r.choseNonUrgent), sum((r) => r.decisions)), 0), 3)}%'
      ' | died at slot T/R/B/L ${fatal[Side.top]}/${fatal[Side.right]}/${fatal[Side.bottom]}/${fatal[Side.left]}',
    );
  }
}

void main(List<String> args) {
  var games = 40;
  var cap = 300.0;
  var suite = 'all';
  var colours = [3, 4];
  for (final arg in args) {
    if (arg.startsWith('--games=')) games = int.parse(arg.substring(8));
    if (arg.startsWith('--cap=')) cap = double.parse(arg.substring(6));
    if (arg.startsWith('--suite=')) suite = arg.substring(8);
    if (arg.startsWith('--variant=')) onlyVariant = arg.substring(10);
    if (arg.startsWith('--colours=')) {
      colours = arg.substring(10).split(',').map(int.parse).toList();
    }
  }
  print('games per row: $games, time cap: ${cap.toStringAsFixed(0)} s\n');
  bool runs(String name) => suite == 'all' || suite == name;
  String seconds(double value) =>
      value == value.roundToDouble() ? value.toStringAsFixed(0) : '$value';

  if (runs('speed')) {
    // (seconds per step in the active glass, in the other glasses)
    const steps = [
      (1.0, 3.0),
      (1.0, 2.0),
      (1.0, 4.0),
      (1.0, 6.0),
      (0.5, 3.0),
      (0.75, 3.0),
      (1.5, 3.0),
      (1.0, 1.0),
    ];
    print('== step intervals x colours, default rules ==');
    for (final colors in colours) {
      for (final (active, inactive) in steps) {
        report(
          'step ${seconds(active)}/${seconds(inactive)} s, $colors col',
          GameConfig(
            activeStepSeconds: active,
            inactiveStepSeconds: inactive,
            numberOfColors: colors,
          ),
          games,
          cap,
        );
      }
      print('');
    }
  }

  if (runs('rules')) {
    const base = GameConfig();
    print('== rule variants (default steps, ${base.numberOfColors} colours) ==');
    report('default', base, games, cap);
    for (final arm in [6, 8, 10]) {
      report('arm $arm cells', base.copyWith(armLength: arm), games, cap);
    }
    report(
      'gravity: above the gap',
      base.copyWith(gravityScope: GravityScope.aboveCleared),
      games,
      cap,
    );
    report(
      'settle on rotation',
      base.copyWith(settleAfterBoardRotation: true),
      games,
      cap,
    );
    report(
      'no pause in cascade',
      base.copyWith(pauseIncomingDuringCascade: false),
      games,
      cap,
    );
  }
}
