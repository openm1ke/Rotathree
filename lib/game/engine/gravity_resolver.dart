import '../config/game_config.dart';
import '../model/board.dart';
import '../model/color.dart';
import '../model/position.dart';
import '../model/side.dart';
import 'rotation_transform.dart';

/// One block falling from [from] to [to] (world coordinates).
class BlockMove {
  const BlockMove(this.from, this.to, this.color);

  final CellPosition from;
  final CellPosition to;
  final BlockColor color;

  /// Number of cells fallen.
  int get distance =>
      (to.row - from.row).abs() + (to.col - from.col).abs();

  @override
  String toString() => '${color.symbol}:$from→$to';
}

/// Plain vertical gravity inside the active glass. "Down" is away from the
/// active side, i.e. towards the bottom of the screen, whichever way the
/// cross is currently turned; the floor is the far wall of the central
/// square. Blocks lying in the three other arms are outside the active glass
/// and never move.
class GravityResolver {
  const GravityResolver();

  /// Lets blocks of the glass of [active] fall until they rest on its floor
  /// or on another block. Mutates [board] and returns what moved.
  ///
  /// With [GravityScope.aboveCleared] only the blocks above a cell listed in
  /// [cleared] (world coordinates) are released.
  List<BlockMove> settle(
    Board board,
    Side active, {
    GravityScope scope = GravityScope.wholeGlass,
    Set<CellPosition> cleared = const {},
  }) {
    final glass = GlassView(board, active);
    final depth = glass.depth;

    // Lowest released row per lane.
    final startRow = List<int>.filled(glass.lanes, depth - 1);
    if (scope == GravityScope.aboveCleared) {
      startRow.fillRange(0, glass.lanes, -1);
      for (final cell in cleared) {
        final local = glass.fromWorld(cell);
        if (local == null) continue; // popped in another glass's arm
        if (local.row - 1 > startRow[local.col]) {
          startRow[local.col] = local.row - 1;
        }
      }
    }

    final moves = <BlockMove>[];
    for (var lane = 0; lane < glass.lanes; lane++) {
      for (var row = startRow[lane]; row >= 0; row--) {
        final color = glass.at(row, lane);
        if (color == null) continue;
        var target = row;
        while (target + 1 < depth && glass.at(target + 1, lane) == null) {
          target++;
        }
        if (target == row) continue;
        glass.set(row, lane, null);
        glass.set(target, lane, color);
        moves.add(
          BlockMove(glass.toWorld(row, lane), glass.toWorld(target, lane), color),
        );
      }
    }
    return moves;
  }
}
