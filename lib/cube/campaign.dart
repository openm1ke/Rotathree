// Cube's campaign: eight levels, each a game of its own with a score to
// reach (webapp/src/cube/campaign.ts). They bring in one thing at a time:
// more colours, a bigger cube, the glasses in front and behind dropping
// their sticks by themselves, quicker falling.
import 'dart:math' as math;

import '../ui/data/progress.dart';
import 'rules.dart';

class CubeLevel {
  const CubeLevel({
    required this.title,
    required this.colours,
    required this.width,
    required this.arm,
    required this.depthFalls,
    required this.target,
    required this.activeStep,
    required this.inactiveStep,
  });

  /// A word or two for the level's tile.
  final String title;
  final int colours;

  /// Side of the cube in the middle, and width of every glass.
  final int width;
  final int arm;

  /// The glasses in front and behind drop their sticks by themselves.
  final bool depthFalls;
  final int target;
  final double activeStep;
  final double inactiveStep;
}

/// The targets were set from a greedy bot that never tips the cube: it
/// reaches each of them on most seeds, a player who tips and turns the cube
/// well before.
const cubeCampaign = <CubeLevel>[
  CubeLevel(title: 'Первые линии', colours: 3, width: 7, arm: 8, depthFalls: false, target: 1500, activeStep: 1, inactiveStep: 3),
  CubeLevel(title: 'Четыре цвета', colours: 4, width: 7, arm: 8, depthFalls: false, target: 2000, activeStep: 1, inactiveStep: 3),
  CubeLevel(title: 'Куб побольше', colours: 4, width: 9, arm: 9, depthFalls: false, target: 2500, activeStep: 1, inactiveStep: 3),
  CubeLevel(title: 'Глубина оживает', colours: 4, width: 9, arm: 9, depthFalls: true, target: 3000, activeStep: 1, inactiveStep: 3),
  CubeLevel(title: 'Пять цветов', colours: 5, width: 9, arm: 9, depthFalls: true, target: 3000, activeStep: 1, inactiveStep: 3),
  CubeLevel(title: 'Быстрее', colours: 5, width: 10, arm: 9, depthFalls: true, target: 3200, activeStep: 0.9, inactiveStep: 2.8),
  CubeLevel(title: 'Шесть цветов', colours: 6, width: 10, arm: 10, depthFalls: true, target: 3400, activeStep: 0.9, inactiveStep: 2.8),
  CubeLevel(title: 'Финал', colours: 6, width: 10, arm: 10, depthFalls: true, target: 3800, activeStep: 0.85, inactiveStep: 2.6),
];

final cubeCampaignLast = cubeCampaign.length - 1;

/// How the endless game speeds up with the score (CUBE_RAMP on the web).
const cubeRamp = CubeRamp(everyPoints: 1500, factor: 0.92, minActive: 0.25, minInactive: 0.8);

/// The rules of a level: no speed-up, the steps are the level's own.
CubeConfig cubeLevelConfig(CubeLevel level) => CubeConfig(
      centre: level.width,
      arm: level.arm,
      numberOfColors: level.colours,
      depthFalls: level.depthFalls,
      activeStepSeconds: level.activeStep,
      inactiveStepSeconds: level.inactiveStep,
    );

Progress defaultCubeProgress() => Progress(unlocked: 0, completed: false, best: List.filled(cubeCampaign.length, 0));

/// Makes sense of a stored Cube campaign progress.
Progress cubeProgressFromJson(Object? raw) {
  final base = defaultCubeProgress();
  if (raw is! Map) return base;
  int whole(Object? value, num max) => value is num && value.isFinite ? value.clamp(0, max).round() : 0;
  final best = raw['best'];
  return Progress(
    unlocked: whole(raw['unlocked'], cubeCampaignLast),
    completed: raw['completed'] == true,
    best: [for (var i = 0; i < cubeCampaign.length; i++) whole(best is List && i < best.length ? best[i] : 0, 1e9)],
  );
}

/// The progress once `index` has been passed with `score`.
Progress passCubeLevel(Progress progress, int index, int score) => Progress(
      unlocked: math.max(progress.unlocked, math.min(index + 1, cubeCampaignLast)),
      completed: progress.completed || index == cubeCampaignLast,
      best: [for (final (i, value) in progress.best.indexed) i == index ? math.max(value, score) : value],
    );
