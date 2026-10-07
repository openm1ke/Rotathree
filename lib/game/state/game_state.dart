import '../engine/gravity_resolver.dart';
import '../engine/match_detector.dart';
import '../engine/placement_engine.dart';
import '../model/board.dart';
import '../model/incoming_piece.dart';
import '../model/piece.dart';
import '../model/side.dart';

/// Explicit phases of the engine. Player input is only applied in [playing];
/// in every other phase it is queued and replayed afterwards, so rotation,
/// drops, pops and gravity can never interleave.
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

  gameOver,
}

/// A hard-dropped piece on its way to where it lands.
class DropInFlight {
  const DropInFlight({required this.placement, required this.startRow});

  final Placement placement;

  /// Row of the piece's top square when the drop began.
  final int startRow;

  Side get side => placement.side;
  Piece get piece => placement.piece;
}

class GameOverInfo {
  const GameOverInfo({required this.side});

  /// The glass that filled up to its far end.
  final Side side;
}

/// Everything the UI needs to draw a frame. Owned and mutated by the engine.
class GameState {
  GameState({required this.board, required this.incoming});

  final Board board;

  /// The piece currently falling down each glass. A glass has no entry while
  /// its piece is being locked and the match it made is resolved.
  final Map<Side, IncomingPiece> incoming;

  Side activeSide = Side.top;
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

  /// Bumped on every change of [board].
  int boardVersion = 0;

  DropInFlight? drop;

  /// Cells flashing (matching / cascading) or popping (clearing).
  MatchResult? activeMatch;

  /// Blocks falling during [GamePhase.settling]. The board already holds them
  /// at their destination.
  List<BlockMove> moves = const [];

  GameOverInfo? gameOver;

  /// 0..1 through the current timed phase.
  double get phaseProgress =>
      phaseDuration <= 0 ? 1 : (phaseElapsed / phaseDuration).clamp(0.0, 1.0);

  bool get isGameOver => phase == GamePhase.gameOver;
}
