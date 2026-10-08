import '../model/board.dart';
import '../model/cell.dart';
import '../model/piece.dart';
import '../model/side.dart';
import 'rotation_transform.dart';

/// Where a piece comes to rest.
class Placement {
  const Placement({
    required this.side,
    required this.piece,
    required this.column,
    required this.row,
    required this.cells,
  });

  final Side side;
  final Piece piece;

  /// Leftmost lane, in the glass of [side].
  final int column;

  /// Row of the piece's top square, in the glass of [side].
  final int row;

  /// The squares in world coordinates, in the piece's colour order.
  final List<PlacedCell> cells;
}

/// Grid-based, deterministic collision of a rigid stick inside a glass.
///
/// A piece of side S lives in the glass of S: it enters at the far end of the
/// arm of S and moves away from it, through the arm and on through the
/// central square, until the next step would hit the floor or a block.
class PlacementEngine {
  const PlacementEngine();

  /// Whether [piece] can occupy whole row [row] at [column] of the glass.
  bool fits(Board board, Side side, Piece piece, int row, int column) {
    // Which square holds which colour does not matter here, only the cells
    // the stick covers: a lying stick runs along its row, a standing one down
    // its lane.
    final length = piece.length;
    if (piece.isHorizontal) {
      for (var i = 0; i < length; i++) {
        if (!glassIsFree(board, side, row, column + i)) return false;
      }
    } else {
      for (var i = 0; i < length; i++) {
        if (!glassIsFree(board, side, row + i, column)) return false;
      }
    }
    return true;
  }

  /// The row where [piece], falling straight down from [fromRow], comes to
  /// rest. Null when it does not even fit at [fromRow].
  int? landingRow(
    Board board,
    Side side,
    Piece piece,
    int column, {
    int fromRow = 0,
  }) {
    if (!fits(board, side, piece, fromRow, column)) return null;
    var row = fromRow;
    while (fits(board, side, piece, row + 1, column)) {
      row++;
    }
    return row;
  }

  /// The piece locked at [row], [column] of its glass.
  Placement placementAt(
    Board board,
    Side side,
    Piece piece,
    int column,
    int row,
  ) {
    final glass = GlassView(board, side);
    final offsets = piece.offsets;
    return Placement(
      side: side,
      piece: piece,
      column: column,
      row: row,
      cells: [
        for (var i = 0; i < piece.length; i++)
          PlacedCell(
            glass.toWorld(row + offsets[i].row, column + offsets[i].col),
            piece.colors[i],
          ),
      ],
    );
  }

  /// Drops [piece] straight down from [fromRow]. Null when it has no room
  /// there.
  Placement? computeDrop(
    Board board,
    Side side,
    Piece piece,
    int column, {
    int fromRow = 0,
  }) {
    final row = landingRow(board, side, piece, column, fromRow: fromRow);
    return row == null ? null : placementAt(board, side, piece, column, row);
  }

  /// Free rows at the far end of the glass of [side] in lanes [column] ..
  /// [column] + [width] - 1: how much room a piece appearing there has.
  int headroom(Board board, Side side, int column, int width) {
    final glass = GlassView(board, side);
    var free = glass.depth;
    for (var lane = column; lane < column + width; lane++) {
      var row = 0;
      while (row < glass.depth && glass.at(row, lane) == null) {
        row++;
      }
      if (row < free) free = row;
    }
    return free;
  }

  /// Every straight drop of [piece] from the far end of the glass of [side],
  /// in all four orientations.
  List<Placement> allPlacements(Board board, Side side, Piece piece) {
    final result = <Placement>[];
    for (final orientation in PieceOrientation.values) {
      final candidate = Piece(piece.colors, orientation: orientation);
      for (var col = 0; col + candidate.width <= board.center; col++) {
        final placement = computeDrop(board, side, candidate, col);
        if (placement != null) result.add(placement);
      }
    }
    return result;
  }
}
