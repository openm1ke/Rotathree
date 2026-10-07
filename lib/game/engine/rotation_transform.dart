import '../model/board.dart';
import '../model/color.dart';
import '../model/position.dart';
import '../model/side.dart';

/// Maps between the fixed world frame of the grid and the *view* frame of a
/// side — the frame in which that side's glass is on top and its pieces fall
/// straight down (row + 1).
///
/// The board data never rotates. Turning the cross only changes which side's
/// frame is used to read it.
class RotationTransform {
  const RotationTransform._();

  static CellPosition viewToWorld(CellPosition view, Side side, int size) {
    final last = size - 1;
    return switch (side) {
      Side.top => view,
      Side.right => CellPosition(view.col, last - view.row),
      Side.bottom => CellPosition(last - view.row, last - view.col),
      Side.left => CellPosition(last - view.col, view.row),
    };
  }

  static CellPosition worldToView(CellPosition world, Side side, int size) {
    final last = size - 1;
    return switch (side) {
      Side.top => world,
      Side.right => CellPosition(last - world.col, world.row),
      Side.bottom => CellPosition(last - world.row, last - world.col),
      Side.left => CellPosition(world.col, last - world.row),
    };
  }

  /// The world side whose glass is drawn in screen slot [slot] while [active]
  /// is on top. With RIGHT active: top slot = RIGHT, right slot = BOTTOM,
  /// bottom slot = LEFT, left slot = TOP.
  static Side sideAtSlot(Side active, Side slot) =>
      Side.values[(active.index + slot.index) % 4];

  /// The screen slot in which the glass of [worldSide] is drawn.
  static Side slotOfSide(Side active, Side worldSide) =>
      Side.values[(worldSide.index - active.index) % 4];

  /// World-frame step (as a row/col delta) of "down" for the given side.
  static CellPosition down(Side side) => switch (side) {
        Side.top => const CellPosition(1, 0),
        Side.right => const CellPosition(0, -1),
        Side.bottom => const CellPosition(-1, 0),
        Side.left => const CellPosition(0, 1),
      };
}

/// One glass: the arm of [side] plus the central square, seen with that side
/// on top. Row 0 is the far end of the arm, the last row is the floor — the
/// far wall of the central square. Lanes run across the glass, 0 on the left.
///
/// The four glasses share the central square; each also owns its own arm.
class GlassView {
  const GlassView(this.board, this.side);

  final Board board;
  final Side side;

  /// Width of the glass.
  int get lanes => board.center;

  /// Number of rows from the far end of the arm to the floor.
  int get depth => board.arm + board.center;

  CellPosition toWorld(int row, int lane) => RotationTransform.viewToWorld(
        CellPosition(row, board.arm + lane),
        side,
        board.size,
      );

  /// The (row, lane) of a world cell in this glass, or null if the cell is in
  /// another glass's arm.
  CellPosition? fromWorld(CellPosition world) {
    final view = RotationTransform.worldToView(world, side, board.size);
    final lane = view.col - board.arm;
    if (lane < 0 || lane >= lanes || view.row < 0 || view.row >= depth) {
      return null;
    }
    return CellPosition(view.row, lane);
  }

  bool contains(int row, int lane) =>
      row >= 0 && row < depth && lane >= 0 && lane < lanes;

  BlockColor? at(int row, int lane) => board.colorAt(toWorld(row, lane));

  void set(int row, int lane, BlockColor? color) {
    final world = toWorld(row, lane);
    board.set(world.row, world.col, color);
  }

  bool isFree(int row, int lane) => contains(row, lane) && at(row, lane) == null;
}
