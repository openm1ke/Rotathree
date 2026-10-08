import 'dart:math' as math;

import '../model/side.dart';
import 'score_rules.dart';

/// Which blocks fall after a match has popped.
enum GravityScope {
  /// Every unsupported block of the active glass falls to rest.
  wholeGlass,

  /// Only the blocks sitting above a popped cell fall — like the rows above a
  /// cleared line. Anything left hanging elsewhere by a turn stays put.
  aboveCleared,
}

/// The order in which glasses are in play: the one the game starts in, then
/// its two neighbours, and the glass opposite it last.
const glassOrder = [Side.top, Side.right, Side.left, Side.bottom];

/// Every tunable of the prototype lives here.
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
    this.initialProgressStagger = 0.15,
    this.spawnColumn,
    this.monoPieceKeepChance = 0.4,
    this.settleAfterBoardRotation = false,
    this.pauseIncomingDuringCascade = true,
    this.gravityScope = GravityScope.wholeGlass,
    this.crowdedHeadroom = 2,
    this.animationSpeed = 1.0,
    this.timeScale = 1.0,
    this.dropBaseSeconds = 0.07,
    this.dropSecondsPerCell = 0.012,
    this.matchSeconds = 0.18,
    this.clearSeconds = 0.22,
    this.fallBaseSeconds = 0.10,
    this.fallSecondsPerRootCell = 0.11,
    this.fallBounceSeconds = 0.14,
    this.rotationSeconds = 0.3,
    this.stepSlideSeconds = 0.12,
    this.maxQueuedInputs = 8,
    this.scoring = const ScoreRules(),
    this.seed,
  })  : assert(boardSize >= pieceLength),
        assert(armLength >= pieceLength),
        assert(glassCount >= 1 && glassCount <= 4),
        assert(numberOfColors >= 2 && numberOfColors <= 6),
        assert(activeStepSeconds > 0 && inactiveStepSeconds > 0),
        assert(animationSpeed > 0);

  /// Side of the central square, and the width of each of the four glasses.
  final int boardSize;

  /// Length of each outer arm, in cells. A glass is one arm plus the central
  /// square, so it is [glassDepth] cells deep.
  final int armLength;

  /// How many of the four glasses are in play, 2 to 4: the one the game
  /// starts in plus one to three more. The arms of the others do not exist.
  final int glassCount;

  /// Number of squares in a stick.
  final int pieceLength;

  /// How many of [BlockColor.values] are in play, 3 to 6.
  final int numberOfColors;

  /// Shortest line of one colour that counts as a match.
  final int minMatchLength;

  /// Pieces fall one whole cell at a time. In the active glass a step comes
  /// this often…
  final double activeStepSeconds;

  /// …and in the three other glasses this often — slowly, so there is time
  /// to think. A piece that cannot take its next step locks instead, so it
  /// always rests for one full step before it does.
  final double inactiveStepSeconds;

  /// While soft drop is held, the active piece steps this often as long as
  /// it has room to fall.
  final double softDropStepSeconds;

  /// Head start, as a fraction of the arm, between the four pieces at the
  /// beginning of a game so they do not all start from the same row.
  final double initialProgressStagger;

  /// Column (leftmost square, in the frame of its own glass) where a new
  /// piece appears. Null centres it.
  final int? spawnColumn;

  /// A stick rolled with a single colour is kept with this probability;
  /// otherwise one of its squares is repainted. 1.0 = no bias.
  final double monoPieceKeepChance;

  /// Experimental: let the blocks of the new active glass fall every time the
  /// cross is turned. Off by default — the structure turns as a rigid body.
  final bool settleAfterBoardRotation;

  /// Freeze all falling pieces while a match is being resolved.
  final bool pauseIncomingDuringCascade;

  /// What falls after a match has popped.
  final GravityScope gravityScope;

  /// A glass with this many free rows or fewer at its far end is flagged as
  /// about to overflow.
  final int crowdedHeadroom;

  /// Multiplier for the engine-timed animations (drop, match, pop, fall).
  final double animationSpeed;

  /// Debug slow motion. Applied by the host loop to the frame delta before it
  /// reaches the engine; the engine itself always works in game seconds.
  final double timeScale;

  final double dropBaseSeconds;
  final double dropSecondsPerCell;

  /// Matched cells flash for this long…
  final double matchSeconds;

  /// …then pop for this long.
  final double clearSeconds;

  /// Blocks released by a pop accelerate downwards: falling `n` cells takes
  /// `fallBaseSeconds + fallSecondsPerRootCell * sqrt(n)`.
  final double fallBaseSeconds;
  final double fallSecondsPerRootCell;

  /// A block that has landed wobbles for this long before play goes on.
  final double fallBounceSeconds;

  /// Duration of the visual 90° turn of the cross (UI only).
  final double rotationSeconds;

  /// How long the short slide of a piece into its next cell takes (UI only;
  /// the step itself is instant).
  final double stepSlideSeconds;

  /// Inputs received while the board is resolving are replayed afterwards;
  /// this caps how many are remembered.
  final int maxQueuedInputs;

  final ScoreRules scoring;

  /// Seed for the piece generator; null = non-deterministic.
  final int? seed;

  /// The glasses in play. Two are neighbours, so that switching is a quarter
  /// turn; three leave out the one opposite the starting glass.
  List<Side> get sides => [for (final side in glassOrder.take(glassCount)) side];

  /// Rows of one glass, from the far end of its arm to its floor (the far
  /// wall of the central square).
  int get glassDepth => armLength + boardSize;

  /// Side of the square grid that contains the whole cross.
  int get gridSize => boardSize + 2 * armLength;

  int get defaultSpawnColumn => (boardSize - pieceLength) ~/ 2;

  /// Flight time of a hard drop over [cells] cells.
  double dropSeconds(double cells) =>
      (dropBaseSeconds + dropSecondsPerCell * cells) / animationSpeed;

  /// Time a released block needs to fall [cells] cells.
  double fallSeconds(int cells) =>
      (fallBaseSeconds + fallSecondsPerRootCell * math.sqrt(cells)) /
      animationSpeed;

  /// Length of the falling phase when the furthest block falls [cells]
  /// cells: its flight plus the wobble on landing.
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
    int? minMatchLength,
    double? activeStepSeconds,
    double? inactiveStepSeconds,
    double? initialProgressStagger,
    int? spawnColumn,
    double? monoPieceKeepChance,
    bool? settleAfterBoardRotation,
    bool? pauseIncomingDuringCascade,
    GravityScope? gravityScope,
    double? animationSpeed,
    double? timeScale,
    int? maxQueuedInputs,
    ScoreRules? scoring,
    int? seed,
  }) {
    return GameConfig(
      boardSize: boardSize ?? this.boardSize,
      armLength: armLength ?? this.armLength,
      glassCount: glassCount ?? this.glassCount,
      pieceLength: pieceLength ?? this.pieceLength,
      numberOfColors: numberOfColors ?? this.numberOfColors,
      minMatchLength: minMatchLength ?? this.minMatchLength,
      activeStepSeconds: activeStepSeconds ?? this.activeStepSeconds,
      inactiveStepSeconds: inactiveStepSeconds ?? this.inactiveStepSeconds,
      softDropStepSeconds: softDropStepSeconds,
      initialProgressStagger:
          initialProgressStagger ?? this.initialProgressStagger,
      spawnColumn: spawnColumn ?? this.spawnColumn,
      monoPieceKeepChance: monoPieceKeepChance ?? this.monoPieceKeepChance,
      settleAfterBoardRotation:
          settleAfterBoardRotation ?? this.settleAfterBoardRotation,
      pauseIncomingDuringCascade:
          pauseIncomingDuringCascade ?? this.pauseIncomingDuringCascade,
      gravityScope: gravityScope ?? this.gravityScope,
      crowdedHeadroom: crowdedHeadroom,
      animationSpeed: animationSpeed ?? this.animationSpeed,
      timeScale: timeScale ?? this.timeScale,
      dropBaseSeconds: dropBaseSeconds,
      dropSecondsPerCell: dropSecondsPerCell,
      matchSeconds: matchSeconds,
      clearSeconds: clearSeconds,
      fallBaseSeconds: fallBaseSeconds,
      fallSecondsPerRootCell: fallSecondsPerRootCell,
      fallBounceSeconds: fallBounceSeconds,
      rotationSeconds: rotationSeconds,
      stepSlideSeconds: stepSlideSeconds,
      maxQueuedInputs: maxQueuedInputs ?? this.maxQueuedInputs,
      scoring: scoring ?? this.scoring,
      seed: seed ?? this.seed,
    );
  }
}
