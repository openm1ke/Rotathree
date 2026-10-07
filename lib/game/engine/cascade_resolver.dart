import '../config/game_config.dart';
import '../model/board.dart';
import '../model/side.dart';
import 'gravity_resolver.dart';
import 'match_detector.dart';

/// One round of a cascade: what matched, what it scored and what fell.
class CascadeStep {
  const CascadeStep({
    required this.combo,
    required this.match,
    required this.score,
    required this.moves,
  });

  /// 1 for the match made by the placement itself, 2 for the first cascade...
  final int combo;
  final MatchResult match;
  final int score;
  final List<BlockMove> moves;
}

class CascadeResult {
  const CascadeResult(this.steps);

  final List<CascadeStep> steps;

  bool get isEmpty => steps.isEmpty;
  int get maxCombo => steps.length;
  int get totalScore => steps.fold(0, (sum, step) => sum + step.score);
  int get clearedCells =>
      steps.fold(0, (sum, step) => sum + step.match.cells.length);
  int get runCount => steps.fold(0, (sum, step) => sum + step.match.runs.length);
}

/// The match → pop → fall loop.
///
/// The engine walks through the same primitives one animated phase at a time;
/// [resolve] runs the whole loop at once (tests, bot look-ahead).
class CascadeResolver {
  CascadeResolver(this.config)
      : _detector = MatchDetector(minLength: config.minMatchLength);

  final GameConfig config;
  final MatchDetector _detector;
  final GravityResolver _gravity = const GravityResolver();

  MatchResult findMatches(Board board) => _detector.find(board);

  int scoreFor(MatchResult match, int combo) {
    var score = 0;
    for (final run in match.runs) {
      score += config.scoring.scoreForRun(
        run.length,
        combo,
        minMatchLength: config.minMatchLength,
      );
    }
    return score;
  }

  void clear(Board board, MatchResult match) {
    for (final cell in match.cells) {
      board.set(cell.row, cell.col, null);
    }
  }

  /// Gravity in the active glass after [match] has popped.
  List<BlockMove> settleAfterClear(Board board, Side active, MatchResult match) =>
      _gravity.settle(
        board,
        active,
        scope: config.gravityScope,
        cleared: match.cells,
      );

  /// Gravity over the whole active glass (used when a turn re-settles it).
  List<BlockMove> settleAll(Board board, Side active) =>
      _gravity.settle(board, active);

  /// Runs one round. Returns null when nothing matches.
  CascadeStep? step(Board board, Side active, int combo) {
    final match = findMatches(board);
    if (match.isEmpty) return null;
    final score = scoreFor(match, combo);
    clear(board, match);
    final moves = settleAfterClear(board, active, match);
    return CascadeStep(combo: combo, match: match, score: score, moves: moves);
  }

  /// Runs rounds until the board is stable. Mutates [board].
  CascadeResult resolve(Board board, Side active) {
    final steps = <CascadeStep>[];
    while (true) {
      final step = this.step(board, active, steps.length + 1);
      if (step == null) break;
      steps.add(step);
    }
    return CascadeResult(steps);
  }
}
