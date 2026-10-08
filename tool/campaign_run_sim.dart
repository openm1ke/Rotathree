// Runs an uninterrupted campaign with the same transitions as the game UI:
// keep the board when adding a glass, reset it when the colour stage changes.
// dart run tool/campaign_run_sim.dart --games=24 --cap=3600 --profile=average
// ignore_for_file: avoid_print
import 'dart:math' as math;
import 'package:rotathree/game/config/campaign.dart';
import 'package:rotathree/game/engine/game_engine.dart';
import 'package:rotathree/game/sim/bot_player.dart';
import 'package:rotathree/game/state/game_state.dart';

String flag(List<String> args, String name, String fallback) =>
    args.firstWhere((arg) => arg.startsWith('--$name='), orElse: () => '--$name=$fallback').substring(name.length + 3);

void main(List<String> args) {
  final games = int.parse(flag(args, 'games', '24'));
  final cap = double.parse(flag(args, 'cap', '3600'));
  final start = int.parse(flag(args, 'start', '1')) - 1;
  final profile = switch (flag(args, 'profile', 'average')) {
    'casual' => BotProfile.casual,
    'expert' => BotProfile.expert,
    'average' => BotProfile.average,
    _ => throw ArgumentError('Unknown profile'),
  };
  if (games < 1 || cap <= 0 || start < 0 || start > campaignLast) throw ArgumentError('Invalid simulation limits');
  const tick = 0.05;
  final times = [for (var i = 0; i < campaignLevels.length; i++) <double>[]];
  var deaths = 0, completed = 0, capped = 0;
  for (var game = 0; game < games; game++) {
    GameEngine engineFor(int level) =>
        GameEngine(config: levelConfig(campaignLevels[level]).copyWith(seed: 1000 + game + level * 997));
    var level = start, base = 0;
    var engine = engineFor(level);
    var bot = BotPlayer(engine, profile: profile, random: math.Random(2000 + game));
    var elapsed = 0.0;
    var banner = 0.0;
    int? pending;
    var done = false;
    while (elapsed < cap && !engine.isGameOver && !done) {
      elapsed += tick;
      if (banner > 0) {
        banner -= tick;
        if (banner > 0) continue;
        if (pending != null) {
          final next = pending;
          pending = null;
          final from = campaignLevels[level], to = campaignLevels[next];
          level = next;
          if (startsStage(level)) {
            engine = engineFor(level);
            bot = BotPlayer(engine, profile: profile, random: math.Random(2000 + game + level * 997));
            base = 0;
            banner = 2.2;
          } else {
            engine.setSteps(to.activeStep, to.inactiveStep);
            if (to.glasses > from.glasses) engine.addGlass();
            base = engine.state.score;
          }
        }
        continue;
      }
      bot.tick(tick);
      engine.update(tick);
      engine.drainEvents();
      if (engine.phase == GamePhase.playing && engine.state.score - base >= campaignLevels[level].target) {
        times[level].add(elapsed);
        if (level == campaignLast) {
          completed++;
          done = true;
        } else {
          pending = level + 1;
          banner = 2.2;
        }
      }
    }
    if (engine.isGameOver) {
      deaths++;
    } else if (!done) {
      capped++;
    }
  }
  print(
    'continuous campaign profile=${profile.name} games=$games start=${start + 1} cap=${cap.round()}s completed=$completed deaths=$deaths capped=$capped',
  );
  print('Times include blocking banners and engine animations. A bot is a heuristic, not a human playtest.');
  for (var level = start; level <= campaignLast; level++) {
    final reached = times[level]..sort();
    final median = reached.isEmpty ? '-' : '${reached[reached.length ~/ 2].round()}s';
    print('level=${level + 1} completed=${reached.length}/$games median=$median');
  }
}
