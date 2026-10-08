import '../model/cell.dart';
import '../model/side.dart';
import 'gravity_resolver.dart';
import 'match_detector.dart';
import 'placement_engine.dart';

/// Things that happened inside the engine, for the UI to react to.
sealed class GameEvent {
  const GameEvent();
}

/// The cross turned from one glass to another.
final class SideSwitched extends GameEvent {
  const SideSwitched({required this.from, required this.to, required this.quarterTurns});

  final Side from;
  final Side to;

  /// Signed number of quarter turns, the short way round.
  final int quarterTurns;
}

/// The active piece slid. [blocked] when a wall or a block stopped it short.
final class PieceMoved extends GameEvent {
  const PieceMoved(this.side, {required this.direction, required this.blocked});

  final Side side;

  /// -1 towards the left of its glass, 1 towards the right.
  final int direction;
  final bool blocked;
}

/// The active piece turned. [blocked] when there was no room to turn.
final class PieceRotated extends GameEvent {
  const PieceRotated(this.side, {required this.blocked});

  final Side side;
  final bool blocked;
}

/// A piece stepped one row down on its own.
final class PieceStepped extends GameEvent {
  const PieceStepped(this.side);

  final Side side;
}

/// The player hard-dropped a piece over [cells] cells.
final class PieceDropped extends GameEvent {
  const PieceDropped(this.side, {required this.cells});

  final Side side;
  final int cells;
}

/// A piece locked into the board.
final class PieceLanded extends GameEvent {
  const PieceLanded(this.placement, {required this.dropped});

  final Placement placement;

  /// True after a hard drop, false when the piece locked by itself.
  final bool dropped;
}

/// A match was found; it will flash and then pop.
final class MatchScored extends GameEvent {
  const MatchScored({required this.combo, required this.score, required this.match});

  final int combo;
  final int score;
  final MatchResult match;
}

/// Matched cells have just been removed from the board.
final class CellsPopped extends GameEvent {
  const CellsPopped(this.cells);

  final List<PlacedCell> cells;
}

/// Blocks have been released and are falling to where they rest.
final class BlocksFell extends GameEvent {
  const BlocksFell(this.moves);

  final List<BlockMove> moves;
}

/// A new glass has been built and its first piece has appeared.
final class GlassAdded extends GameEvent {
  const GlassAdded(this.side);

  final Side side;
}

/// The score passed another step of a speed ramp.
final class SpeedUp extends GameEvent {
  const SpeedUp({required this.level, required this.activeStep, required this.inactiveStep});

  final int level;
  final double activeStep;
  final double inactiveStep;
}

/// A glass overflowed: the game is over.
final class GameEnded extends GameEvent {
  const GameEnded(this.side);

  final Side side;
}
