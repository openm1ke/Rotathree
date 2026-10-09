import '../engine/gravity_resolver.dart';
import '../engine/match_detector.dart';
import '../engine/placement_engine.dart';
import '../model/board.dart';
import '../model/incoming_piece.dart';
import '../model/side.dart';

/// Explicit phases of the engine. Input is applied in [playing]; movement
/// and turns can be queued during resolution, but hard drops are never buffered.
enum GamePhase {
  /// Pieces fall; the player can switch, move, rotate and drop.
  playing,

  /// A hard-dropped piece is flying to its resting place.
  pieceDropping,

  /// The match made by a placement is flashing.
  matching,

  /// Matched cells are popping.
  clearing,

  /// Blocks are falling into the freed space.
  settling,

  /// A follow-up match (combo ×2 and up) is flashing.
  cascading,

  /// A new glass is being built; its first piece appears at the end.
  building,

  gameOver,
}

/// A hard-dropped piece on its way to where it lands.
class DropInFlight {
  const DropInFlight({required this.placement, required this.startRow});

  final Placement placement;

  /// Row of the piece's top square when the drop began.
  final int startRow;
}

/// Everything the UI needs to draw a frame. Owned and mutated by the engine.
class GameState {
  GameState({
    required this.board,
    required this.incoming,
    required this.activeSide,
  });

  final Board board;

  /// The piece currently falling down each glass in play.
  final Map<Side, IncomingPiece> incoming;

  Side activeSide;
  GamePhase phase = GamePhase.playing;
  double phaseElapsed = 0;
  double phaseDuration = 0;

  int score = 0;

  /// Combo level of the chain being resolved (0 when idle).
  int combo = 0;
  int bestCombo = 0;

  /// Number of matched lines popped so far.
  int matches = 0;
  int clearedCells = 0;
  int piecesPlaced = 0;

  /// Pieces that locked on their own, without a hard drop by the player.
  int selfLocked = 0;
  double elapsedSeconds = 0;

  /// Bumped on every change of [board], so that plans made on it can tell.
  int boardVersion = 0;

  DropInFlight? drop;

  /// Cells flashing (matching / cascading) or popping (clearing).
  MatchResult? activeMatch;

  /// Blocks falling during [GamePhase.settling]; the board already holds them
  /// at their destination.
  List<BlockMove> moves = const [];

  /// The glass being built during [GamePhase.building].
  Side? buildingSide;

  /// How many speed-ups the score has earned (0 without a ramp).
  int speedLevel = 0;

  /// The glass that overflowed, once the game is over.
  Side? gameOverSide;

  /// 0..1 through the current timed phase.
  double get phaseProgress =>
      phaseDuration <= 0 ? 1 : (phaseElapsed / phaseDuration).clamp(0.0, 1.0);

  bool get isGameOver => phase == GamePhase.gameOver;
}
