// Calibrates the campaign: how long bots of each skill take to reach a number
// of points with a given number of glasses and colours.
//
//   dart run tool/campaign_sim.dart --glasses=2 --colours=4 --active=1
//       --inactive=3 --games=24 --cap=600 --profile=average
//
// Prints one line per target score: the share of games that reached it and
// the median time it took, in seconds.
// ignore_for_file: avoid_print

import 'dart:math' as math;

import 'package:rotathree/game/config/game_config.dart';
import 'package:rotathree/game/engine/game_engine.dart';
import 'package:rotathree/game/sim/bot_player.dart';

const _tick = 0.1;

const _targets = [
  200, 300, 400, 500, 600, 800, 1000, 1200, 1400, 1600, 1800, 2000, 2300,
  2600, 3000, 3400, 3800, 4200, 4700, 5200, 5800, 6400, 7000, 7700, 8500,
  9400, 10400, 11500, 12700, 14000,
];

String _flag(List<String> args, String name, String fallback) {
  for (final arg in args) {
    if (arg.startsWith('--$name=')) return arg.substring(name.length + 3);
  }
  return fallback;
}

void main(List<String> args) {
  final glasses = int.parse(_flag(args, 'glasses', '1'));
  final colours = int.parse(_flag(args, 'colours', '3'));
  final active = double.parse(_flag(args, 'active', '1'));
  final inactive = double.parse(_flag(args, 'inactive', '3'));
  final games = int.parse(_flag(args, 'games', '24'));
  final cap = double.parse(_flag(args, 'cap', '600'));
  final profileName = _flag(args, 'profile', 'average');
  final profile = switch (profileName) {
    'casual' => BotProfile.casual,
    'expert' => BotProfile.expert,
    _ => BotProfile.average,
  };

  final times = {for (final target in _targets) target: <double>[]};
  var deaths = 0;
  for (var g = 0; g < games; g++) {
    final config = GameConfig(
      glassCount: glasses,
      numberOfColors: colours,
      activeStepSeconds: active,
      inactiveStepSeconds: inactive,
      seed: 1000 + g,
    );
    final engine = GameEngine(config: config, random: math.Random(1000 + g));
    final bot = BotPlayer(engine, profile: profile, random: math.Random(2000 + g));
    final hit = <int, double>{};
    var t = 0.0;
    while (!engine.isGameOver && t < cap && hit.length < _targets.length) {
      bot.tick(_tick);
      engine.update(_tick);
      t += _tick;
      final score = engine.state.score;
      for (final target in _targets) {
        if (score >= target) hit.putIfAbsent(target, () => t);
      }
    }
    if (engine.isGameOver) deaths++;
    for (final target in _targets) {
      final at = hit[target];
      if (at != null) times[target]!.add(at);
    }
  }

  print('glasses=$glasses colours=$colours active=$active inactive=$inactive '
      'profile=$profileName games=$games deaths=$deaths cap=${cap.round()}');
  for (final target in _targets) {
    final list = times[target]!..sort();
    final share = list.length / games;
    final median = list.isEmpty ? double.nan : list[list.length ~/ 2];
    print('  $target ${(share * 100).round()}% ${median.isNaN ? '-' : median.round()}s');
  }
}
