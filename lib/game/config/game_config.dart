import 'dart:math' as math;

import '../model/side.dart';
import 'score_rules.dart';

/// Which blocks fall after a match has popped.
enum GravityScope {
  /// Every unsupported block of the active glass falls to rest.
  wholeGlass,

  /// Only the blocks sitting above a popped cell fall.
  aboveCleared,
}

/// The order in which glasses come into play: the one the game starts in,
/// its two neighbours, and the glass opposite it last.
const glassOrder = [Side.top, Side.right, Side.left, Side.bottom];

/// Every tunable of the game lives here.
class GameConfig {
  const GameConfig({
    this.boardSize = 10,
    this.armLength = 9,
    this.glassCount = 4,
    this.pieceLength = 3,
    this.numberOfColors = 3,
    this.minMatchLength = 3,
    this.activeStepSeconds = 1.0,
    this.inactiveStepSeconds = 3.0,
    this.softDropStepSeconds = 0.05,
    this.buildSeconds = 1.1,
    this.initialProgressStagger = 0.15,
    this.spawnColumn,
    this.monoPieceKeepChance = 0.4,
    this.settleAfterBoardRotation = false,
    this.pauseIncomingDuringCascade = true,
    this.gravityScope = GravityScope.wholeGlass,
    this.crowdedHeadroom = 2,
    this.animationSpeed = 1.0,
    this.dropBaseSeconds = 0.06,
    this.dropSecondsPerCell = 0.008,
    this.matchSeconds = 0.16,
    this.clearSeconds = 0.2,
    this.fallBaseSeconds = 0.09,
    this.fallSecondsPerRootCell = 0.1,
    this.fallBounceSeconds = 0.12,
    this.maxQueuedInputs = 8,
    this.scoring = const ScoreRules(),
    this.seed,
  })  : assert(boardSize >= pieceLength),
        assert(armLength >= pieceLength),
        assert(glassCount >= 1 && glassCount <= 4),
        assert(numberOfColors >= 2 && numberOfColors <= 9),
        assert(activeStepSeconds > 0 && inactiveStepSeconds > 0),
        assert(animationSpeed > 0);

  /// Side of the central square, and the width of each of the four glasses.
  final int boardSize;

  /// Length of each outer arm, in cells.
  final int armLength;

  /// How many of the four glasses are in play when a game starts (1 to 4).
  final int glassCount;

  /// Number of squares in a stick.
  final int pieceLength;

  /// How many of [BlockColor.values] are in play (3 to 9).
  final int numberOfColors;

  /// Shortest line of one colour that counts as a match.
  final int minMatchLength;

  /// Seconds between two steps of the active glass.
  final double activeStepSeconds;

  /// Seconds between two steps of the other glasses.
  final double inactiveStepSeconds;

  /// While soft drop is held, the active piece steps this often.
  final double softDropStepSeconds;

  /// How long building a new glass takes.
  final double buildSeconds;

  /// Head start, as a fraction of the arm, between the pieces at the start.
  final double initialProgressStagger;

  /// Column (leftmost square, in the frame of its own glass) where a new piece
  /// appears. Null centres it.
  final int? spawnColumn;

  /// A stick rolled with a single colour is kept with this probability.
  final double monoPieceKeepChance;

  /// Let the blocks of the new active glass fall every time the cross turns.
  final bool settleAfterBoardRotation;

  /// Freeze all falling pieces while a match is being resolved.
  final bool pauseIncomingDuringCascade;

  /// What falls after a match has popped.
  final GravityScope gravityScope;

  /// A glass with this many free rows or fewer at its far end is flagged.
  final int crowdedHeadroom;

  /// Multiplier for the engine-timed animations.
  final double animationSpeed;

  final double dropBaseSeconds;
  final double dropSecondsPerCell;

  /// Matched cells flash for this long…
  final double matchSeconds;

  /// …then pop for this long.
  final double clearSeconds;

  final double fallBaseSeconds;
  final double fallSecondsPerRootCell;

  /// A block that has landed wobbles for this long before play goes on.
  final double fallBounceSeconds;

  /// Inputs received while the board resolves are replayed afterwards.
  final int maxQueuedInputs;

  final ScoreRules scoring;

  /// Seed for the piece generator; null = non-deterministic.
  final int? seed;

  /// The glasses in play at the start, in the order they came into play.
  List<Side> get sides => [for (final side in glassOrder.take(glassCount)) side];

  /// Rows of one glass, from the far end of its arm to its floor.
  int get glassDepth => armLength + boardSize;

  /// Side of the square grid that contains the whole cross.
  int get gridSize => boardSize + 2 * armLength;

  int get defaultSpawnColumn => (boardSize - pieceLength) ~/ 2;

  /// Flight time of a hard drop over [cells] cells.
  double dropSeconds(num cells) =>
      (dropBaseSeconds + dropSecondsPerCell * cells) / animationSpeed;

  /// Time a released block needs to fall [cells] cells.
  double fallSeconds(int cells) =>
      (fallBaseSeconds + fallSecondsPerRootCell * math.sqrt(cells)) /
      animationSpeed;

  /// Length of the falling phase when the furthest block falls [cells] cells.
  double fallPhaseSeconds(int cells) =>
      fallSeconds(cells) + fallBounceSeconds / animationSpeed;

  double get matchPhaseSeconds => matchSeconds / animationSpeed;
  double get clearPhaseSeconds => clearSeconds / animationSpeed;

  GameConfig copyWith({
    int? boardSize,
    int? armLength,
    int? glassCount,
    int? pieceLength,
    int? numberOfColors,
    double? activeStepSeconds,
    double? inactiveStepSeconds,
    double? buildSeconds,
    int? spawnColumn,
    bool? settleAfterBoardRotation,
    bool? pauseIncomingDuringCascade,
    GravityScope? gravityScope,
    int? maxQueuedInputs,
    int? seed,
  }) {
    return GameConfig(
      boardSize: boardSize ?? this.boardSize,
      armLength: armLength ?? this.armLength,
      glassCount: glassCount ?? this.glassCount,
      pieceLength: pieceLength ?? this.pieceLength,
      numberOfColors: numberOfColors ?? this.numberOfColors,
      minMatchLength: minMatchLength,
      activeStepSeconds: activeStepSeconds ?? this.activeStepSeconds,
      inactiveStepSeconds: inactiveStepSeconds ?? this.inactiveStepSeconds,
      softDropStepSeconds: softDropStepSeconds,
      buildSeconds: buildSeconds ?? this.buildSeconds,
      initialProgressStagger: initialProgressStagger,
      spawnColumn: spawnColumn ?? this.spawnColumn,
      monoPieceKeepChance: monoPieceKeepChance,
      settleAfterBoardRotation: settleAfterBoardRotation ?? this.settleAfterBoardRotation,
      pauseIncomingDuringCascade: pauseIncomingDuringCascade ?? this.pauseIncomingDuringCascade,
      gravityScope: gravityScope ?? this.gravityScope,
      crowdedHeadroom: crowdedHeadroom,
      animationSpeed: animationSpeed,
      dropBaseSeconds: dropBaseSeconds,
      dropSecondsPerCell: dropSecondsPerCell,
      matchSeconds: matchSeconds,
      clearSeconds: clearSeconds,
      fallBaseSeconds: fallBaseSeconds,
      fallSecondsPerRootCell: fallSecondsPerRootCell,
      fallBounceSeconds: fallBounceSeconds,
      maxQueuedInputs: maxQueuedInputs ?? this.maxQueuedInputs,
      scoring: scoring,
      seed: seed ?? this.seed,
    );
  }
}
