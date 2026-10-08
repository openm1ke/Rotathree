import 'dart:math' as math;

import '../config/game_config.dart';
import '../model/board.dart';
import '../model/incoming_piece.dart';
import '../model/piece.dart';
import '../model/side.dart';
import 'piece_generator.dart';
import 'placement_engine.dart';

/// Owns the independent streams of falling pieces, one per glass in play.
///
/// Every piece falls along its own glass one whole cell per step. Steps come
/// quickly in the active glass and slowly in the others. A piece whose next
/// step is blocked locks instead.
class IncomingController {
  IncomingController(this.config, this.generator);

  /// Absorbs floating-point error when a step falls due.
  static const _epsilon = 1e-9;

  GameConfig config;
  final PieceGenerator generator;
  final PlacementEngine _placement = const PlacementEngine();
  final Map<Side, IncomingPiece> _pieces = {};

  /// The last landing row worked out for each glass, and what it was worked
  /// out from. It is asked for several times a frame and changes once a step.
  final Map<Side, _RestRow> _rest = {};

  /// While true, the active piece steps at the soft-drop rate as long as it
  /// has room to fall.
  bool softDrop = false;

  Map<Side, IncomingPiece> get pieces => _pieces;

  /// Uses new step times and rules from now on.
  void setConfig(GameConfig value) => config = value;

  IncomingPiece? pieceAt(Side side) => _pieces[side];

  int get spawnColumn => config.spawnColumn ?? config.defaultSpawnColumn;

  /// Seconds between two steps of the piece of [side] while [active] is on top.
  double baseStepSeconds(Side side, Side active) =>
      side == active ? config.activeStepSeconds : config.inactiveStepSeconds;

  /// Seconds between two steps of [piece] right now.
  double stepSeconds(IncomingPiece piece, Side active, Board board) {
    if (piece.side != active) return config.inactiveStepSeconds;
    // Soft drop only speeds up actual falling: a piece that has landed keeps
    // its full step to be slid or turned before it locks.
    if (softDrop &&
        _placement.fits(board, piece.side, piece.piece, piece.row + 1, piece.column)) {
      return math.min(config.softDropStepSeconds, config.activeStepSeconds);
    }
    return config.activeStepSeconds;
  }

  /// Starts a fresh game: one piece per glass in [sides], staggered so that
  /// the first glass is the furthest along.
  void reset(List<Side> sides) {
    _pieces.clear();
    softDrop = false;
    for (var i = 0; i < sides.length; i++) {
      final headStart = (sides.length - 1 - i) * config.initialProgressStagger;
      put(sides[i], generator.next(), row: (headStart * config.armLength).round());
    }
  }

  /// Puts a new piece at the far end of [side]'s glass. Returns null when the
  /// glass is full up to there — the game is over.
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
      column: (column ?? spawnColumn).clamp(0, config.boardSize - piece.width).toInt(),
      row: row,
      stepProgress: stepProgress,
    );
    _pieces[side] = incoming;
    return incoming;
  }

  /// Removes and returns the piece of [side] (it is being locked).
  IncomingPiece? take(Side side) => _pieces.remove(side);

  /// The row where [piece] will come to rest if nothing changes.
  int restRow(IncomingPiece piece, Board board) {
    final known = _rest[piece.side];
    if (known != null &&
        identical(known.board, board) &&
        known.version == board.version &&
        identical(known.piece, piece.piece) &&
        known.row == piece.row &&
        known.column == piece.column) {
      return known.value;
    }
    final value = _placement.landingRow(
          board,
          piece.side,
          piece.piece,
          piece.column,
          fromRow: piece.row,
        ) ??
        piece.row;
    _rest[piece.side] = _RestRow(board, board.version, piece.piece, piece.row, piece.column, value);
    return value;
  }

  /// Seconds until [piece] locks by itself if it is left alone.
  double secondsToLock(IncomingPiece piece, Board board, Side active) {
    final stepsDown = restRow(piece, board) - piece.row;
    return (1 - piece.stepProgress + stepsDown) * baseStepSeconds(piece.side, active);
  }

  /// Seconds until the first piece is due to step; null if no glass holds one.
  double? secondsToNextStep(Side active, Board board) {
    double? best;
    for (final piece in _pieces.values) {
      final left = (1 - piece.stepProgress) * stepSeconds(piece, active, board);
      if (best == null || left < best) best = left;
    }
    return best == null ? null : math.max(0, best);
  }

  bool _isDue(Side side) => (_pieces[side]?.stepProgress ?? 0) >= 1 - _epsilon;

  /// Sides whose piece is due to step, the active one first.
  List<Side> dueSides(Side active) => [
        if (_isDue(active)) active,
        for (final side in Side.values)
          if (side != active && _isDue(side)) side,
      ];

  /// Lets [seconds] pass for every piece. Nothing moves here: a piece only
  /// becomes due for its next step (see [step]).
  void advance(double seconds, Side active, Board board) {
    if (seconds <= 0) return;
    for (final piece in _pieces.values) {
      final progress = piece.stepProgress + seconds / stepSeconds(piece, active, board);
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

  /// Slides the piece of [side] sideways by [delta] lanes, stopping at a wall
  /// or a settled block. Returns the lanes it actually moved.
  int move(Side side, int delta, Board board) {
    final piece = _pieces[side];
    if (piece == null || delta == 0) return 0;
    return setColumn(side, piece.column + delta, board);
  }

  /// Slides the piece of [side] towards lane [column] one lane at a time,
  /// stopping at the wall or at a settled block. Returns the lanes moved.
  int setColumn(Side side, int column, Board board) {
    final piece = _pieces[side];
    if (piece == null) return 0;
    final step = column > piece.column ? 1 : -1;
    var moved = 0;
    while (piece.column != column) {
      final next = piece.column + step;
      if (!_placement.fits(board, side, piece.piece, piece.row, next)) break;
      piece.column = next;
      moved++;
    }
    return moved;
  }

  /// Turns the stick of [side] a quarter turn around its middle square. The
  /// colour order never changes. Returns false when there is no room to turn.
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
  IncomingPiece? rotated(
    IncomingPiece piece,
    Board board, {
    bool clockwise = true,
  }) {
    final pivot = piece.piece.length ~/ 2;
    final turned = clockwise ? piece.piece.rotated() : piece.piece.rotatedBack();
    final column = turned.isHorizontal ? piece.column - pivot : piece.column + pivot;
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

  /// Call after settled blocks appeared in new cells. A falling piece that now
  /// overlaps one of them is moved back towards the far end of its glass.
  /// Returns the sides whose piece has no room left at all.
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

/// A landing row and everything it depends on.
class _RestRow {
  const _RestRow(this.board, this.version, this.piece, this.row, this.column, this.value);

  final Board board;
  final int version;
  final Piece piece;
  final int row;
  final int column;
  final int value;
}
