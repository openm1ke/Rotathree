/// Scoring formula, kept apart from the engine so it can be tuned on its own.
class ScoreRules {
  const ScoreRules({this.basePoints = 100});

  /// Points for the shortest possible match.
  final int basePoints;

  /// Base value of one matched line: 3 → 100, 4 → 200, 5 → 300, 6 → 400 ...
  int runBase(int runLength, {int minMatchLength = 3}) {
    if (runLength < minMatchLength) return 0;
    return basePoints * (runLength - minMatchLength + 1);
  }

  /// Value of one matched line at the given combo level (1 = first match).
  int scoreForRun(int runLength, int comboLevel, {int minMatchLength = 3}) {
    return runBase(runLength, minMatchLength: minMatchLength) * comboLevel;
  }
}
