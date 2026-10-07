import '../config/game_config.dart';
import '../model/board.dart';
import '../model/incoming_piece.dart';
import '../model/piece.dart';
import '../model/side.dart';
import 'piece_generator.dart';
import 'placement_engine.dart';

/// Owns the four independent streams of falling pieces, one per glass.
///
/// Every piece falls along its own glass — through the arm and on through the
/// central square — one whole cell per step. Steps come quickly in the active
/// glass and slowly in the other three. A piece whose next step is blocked
/// locks instead. Falling pieces do not collide with each other, only with
/// settled blocks.
class IncomingController {
  IncomingController(this.config, this.generator);

  /// Absorbs floating-point error when a step falls due.
  static const _epsilon = 1e-9;

  final GameConfig config;
  final PieceGenerator generator;
  final PlacementEngine _placement = const PlacementEngine();
  final Map<Side, IncomingPiece> _pieces = {};

  Map<Side, IncomingPiece> get pieces => _pieces;

  IncomingPiece? pieceAt(Side side) => _pieces[side];

  int get spawnColumn => config.spawnColumn ?? config.defaultSpawnColumn;

  /// Seconds between two steps of the piece of [side] while [active] is the
  /// glass on top.
  double stepSeconds(Side side, Side active) =>
      side == active ? config.activeStepSeconds : config.inactiveStepSeconds;

  /// Starts a fresh game: one piece per glass, staggered so that TOP is the
  /// furthest along and LEFT starts at the very end of its arm.
  void reset() {
    _pieces.clear();
    for (final side in Side.values) {
      final headStart = (Side.values.length - 1 - side.index) *
          config.initialProgressStagger;
      put(side, generator.next(), row: (headStart * config.armLength).round());
    }
  }

  /// Puts a new piece at the far end of [side]'s glass. Returns null when
  /// the glass is full up to there — the game is over.
  IncomingPiece? spawn(Side side, Board board) {
    final piece = generator.next();
    if (!_placement.fits(board, side, piece, 0, spawnColumn)) return null;
    return put(side, piece);
  }

  /// Places a specific piece in a glass (spawning, tests, debugging).
  IncomingPiece put(
    Side side,
    Piece piece, {
    int? column,
    int row = 0,
    double stepProgress = 0,
  }) {
    final incoming = IncomingPiece(
      side: side,
      piece: piece,
      column: (column ?? spawnColumn).clamp(0, config.boardSize - piece.width),
      row: row,
      stepProgress: stepProgress,
    );
    _pieces[side] = incoming;
    return incoming;
  }

  /// Removes and returns the piece of [side] (it is being locked).
  IncomingPiece? take(Side side) => _pieces.remove(side);

  /// The row where [piece] will come to rest if nothing changes.
  int restRow(IncomingPiece piece, Board board) =>
      _placement.landingRow(
        board,
        piece.side,
        piece.piece,
        piece.column,
        fromRow: piece.row,
      ) ??
      piece.row;

  /// Seconds until [piece] locks by itself if it is left alone and [active]
  /// stays on top: the steps down to where it rests, plus the one step it
  /// then fails to take.
  double secondsToLock(IncomingPiece piece, Board board, Side active) {
    final stepsDown = restRow(piece, board) - piece.row;
    return (1 - piece.stepProgress + stepsDown) *
        stepSeconds(piece.side, active);
  }

  /// Seconds until the first piece is due to step; null if no glass holds a
  /// piece.
  double? secondsToNextStep(Side active) {
    double? best;
    for (final piece in _pieces.values) {
      final left = (1 - piece.stepProgress) * stepSeconds(piece.side, active);
      if (best == null || left < best) best = left;
    }
    return best == null ? null : (best < 0 ? 0 : best);
  }

  /// Sides whose piece is due to step, the active one first, then side order.
  List<Side> dueSides(Side active) => [
        if (_isDue(active)) active,
        for (final side in Side.values)
          if (side != active && _isDue(side)) side,
      ];

  bool _isDue(Side side) =>
      (_pieces[side]?.stepProgress ?? 0) >= 1 - _epsilon;

  /// Lets [seconds] pass for every piece. Nothing moves here: a piece only
  /// becomes due for its next step (see [step]).
  void advance(double seconds, Side active) {
    if (seconds <= 0) return;
    for (final piece in _pieces.values) {
      final progress =
          piece.stepProgress + seconds / stepSeconds(piece.side, active);
      piece.stepProgress = progress >= 1 - _epsilon ? 1 : progress;
    }
  }

  /// Takes the due step of the piece of [side]: one row down. Returns false
  /// when that row is blocked — the piece has to lock where it is.
  bool step(Side side, Board board) {
    final piece = _pieces[side];
    if (piece == null) return true;
    if (!_placement.fits(board, side, piece.piece, piece.row + 1, piece.column)) {
      return false;
    }
    piece.row++;
    piece.stepProgress = 0;
    return true;
  }

  /// Slides the piece of [side] sideways one lane at a time, stopping at the
  /// wall of the glass or at a settled block.
  bool move(Side side, int delta, Board board) {
    final piece = _pieces[side];
    if (piece == null || delta == 0) return false;
    return setColumn(side, piece.column + delta, board);
  }

  bool setColumn(Side side, int column, Board board) {
    final piece = _pieces[side];
    if (piece == null) return false;
    final step = column > piece.column ? 1 : -1;
    var moved = false;
    while (piece.column != column) {
      final next = piece.column + step;
      if (!_placement.fits(board, side, piece.piece, piece.row, next)) break;
      piece.column = next;
      moved = true;
    }
    return moved;
  }

  /// Turns the stick a quarter turn around its middle square — clockwise by
  /// default. If it does not fit there it is nudged sideways or along the
  /// glass; if nothing fits it stays as it was. The colour order never
  /// changes: four turns bring the first colour to the left, the top, the
  /// right and the bottom.
  bool rotate(Side side, Board board, {bool clockwise = true}) {
    final piece = _pieces[side];
    if (piece == null) return false;
    final turned = rotated(piece, board, clockwise: clockwise);
    if (turned == null) return false;
    piece.piece = turned.piece;
    piece.column = turned.column;
    piece.row = turned.row;
    return true;
  }

  /// Where [piece] would be after a rotation, or null if it cannot turn.
  /// Does not change anything.
  IncomingPiece? rotated(
    IncomingPiece piece,
    Board board, {
    bool clockwise = true,
  }) {
    final pivot = piece.piece.length ~/ 2;
    final turned =
        clockwise ? piece.piece.rotated() : piece.piece.rotatedBack();
    final column =
        turned.isHorizontal ? piece.column - pivot : piece.column + pivot;
    final row = turned.isHorizontal ? piece.row + pivot : piece.row - pivot;

    // (rows, lanes) nudges, gentlest first.
    const kicks = [
      (0, 0), (0, -1), (0, 1), (-1, 0), (1, 0),
      (0, -2), (0, 2), (-1, -1), (-1, 1), (-2, 0),
    ];
    for (final (rows, lanes) in kicks) {
      if (_placement.fits(board, piece.side, turned, row + rows, column + lanes)) {
        return IncomingPiece(
          side: piece.side,
          piece: turned,
          column: column + lanes,
          row: row + rows,
          stepProgress: piece.stepProgress,
        );
      }
    }
    return null;
  }

  /// Lanes the piece can slide to from where it is, nearest first.
  List<int> reachableColumns(IncomingPiece piece, Board board) {
    final columns = [piece.column];
    for (final step in const [-1, 1]) {
      var column = piece.column + step;
      while (_placement.fits(board, piece.side, piece.piece, piece.row, column)) {
        columns.add(column);
        column += step;
      }
    }
    return columns;
  }

  /// Call after settled blocks appeared in new cells (a lock, a fall). A
  /// falling piece that now overlaps one of them is moved back towards the
  /// far end of its own glass until it fits again. Returns the sides whose
  /// piece has no room left at all.
  List<Side> resolveOverlaps(Board board) {
    final crushed = <Side>[];
    for (final piece in _pieces.values) {
      var row = piece.row;
      while (row >= 0 &&
          !_placement.fits(board, piece.side, piece.piece, row, piece.column)) {
        row--;
      }
      if (row < 0) {
        crushed.add(piece.side);
      } else {
        piece.row = row;
      }
    }
    return crushed;
  }
}
