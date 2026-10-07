/// Zen mode: the same game played through levels. Each level asks for a few
/// more points than the one before; nothing gets faster.
abstract final class ZenLevels {
  /// Points needed to finish [level] (the first level is 1).
  static int target(int level) => 1000 + 500 * (level - 1);

  /// Total score at which [level] begins.
  static int start(int level) {
    var total = 0;
    for (var l = 1; l < level; l++) {
      total += target(l);
    }
    return total;
  }

  /// The level a total score has reached.
  static int levelOf(int score) {
    var level = 1;
    while (score >= start(level + 1)) {
      level++;
    }
    return level;
  }

  /// How far into [level] a total score is, capped at the level's target:
  /// the score may run past it while a cascade is still resolving.
  static int into(int score, int level) =>
      (score - start(level)).clamp(0, target(level));
}
