/// A speed that rises with the score: every [everyPoints] the step times are
/// multiplied by [factor], never going below the minimums.
class SpeedRamp {
  const SpeedRamp({
    required this.everyPoints,
    required this.factor,
    required this.minActive,
    required this.minInactive,
  });

  final int everyPoints;
  final double factor;
  final double minActive;
  final double minInactive;
}
