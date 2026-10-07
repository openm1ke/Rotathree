import 'piece.dart';
import 'side.dart';

/// A stick falling down one of the four glasses, one whole cell at a time.
class IncomingPiece {
  IncomingPiece({
    required this.side,
    required this.piece,
    required this.column,
    this.row = 0,
    this.stepProgress = 0,
  });

  final Side side;
  Piece piece;

  /// Leftmost lane across the glass, in the frame of its own side (the way
  /// the glass looks when it is the active one, on top).
  int column;

  /// Row of the piece's top square, counted from the far end of its glass.
  int row;

  /// How far the wait for its next step has got, 0..1. Kept as a fraction so
  /// that it carries over when its glass becomes active (and steps come
  /// faster) or stops being active.
  double stepProgress;

  IncomingPiece copy() => IncomingPiece(
        side: side,
        piece: piece,
        column: column,
        row: row,
        stepProgress: stepProgress,
      );

  @override
  String toString() =>
      '${side.name}:$piece@$column r$row +${stepProgress.toStringAsFixed(2)}';
}
