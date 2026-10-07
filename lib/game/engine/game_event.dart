import '../model/cell.dart';
import '../model/side.dart';
import '../state/game_state.dart';
import 'match_detector.dart';
import 'placement_engine.dart';

/// Things that happened inside the engine, for the UI to react to
/// (animations, haptics). The engine never depends on who listens.
sealed class GameEvent {
  const GameEvent();
}

class SideSwitched extends GameEvent {
  const SideSwitched(this.from, this.to, this.quarterTurns);

  final Side from;
  final Side to;

  /// Signed number of steps in the TOP → RIGHT → BOTTOM → LEFT order.
  final int quarterTurns;
}

/// The player slid the active piece; [blocked] when a wall or a block
/// stopped it short.
class PieceMoved extends GameEvent {
  const PieceMoved(this.side, this.direction, {required this.blocked});

  final Side side;

  /// -1 towards the left of its glass, 1 towards the right.
  final int direction;
  final bool blocked;
}

/// The player turned the active piece; [blocked] when it had no room.
class PieceRotated extends GameEvent {
  const PieceRotated(this.side, {required this.blocked});

  final Side side;
  final bool blocked;
}

/// The player hard-dropped the active piece.
class PieceDropped extends GameEvent {
  const PieceDropped(this.side);

  final Side side;
}

/// A piece locked into the board.
class PieceLanded extends GameEvent {
  const PieceLanded(this.placement, {required this.dropped});

  final Placement placement;

  /// True after a hard drop, false when the piece settled by itself.
  final bool dropped;
}

/// A match was found; it will flash and then pop.
class MatchScored extends GameEvent {
  const MatchScored({
    required this.combo,
    required this.score,
    required this.match,
  });

  final int combo;
  final int score;
  final MatchResult match;
}

/// Matched cells have just been removed from the board.
class CellsPopped extends GameEvent {
  const CellsPopped(this.cells);

  final List<PlacedCell> cells;
}

class GameEnded extends GameEvent {
  const GameEnded(this.info);

  final GameOverInfo info;
}
