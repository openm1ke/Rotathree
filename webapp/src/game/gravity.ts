import { EMPTY, type Board } from './board';
import type { GravityScope } from './config';
import { GlassView, type Cell } from './glass';
import type { BlockColor } from './piece';
import type { Side } from './side';

/** One block falling from `from` to `to` (world coordinates). */
export interface BlockMove {
  from: Cell;
  to: Cell;
  color: BlockColor;
  /** Number of cells fallen. */
  distance: number;
}

/** Plain vertical gravity inside the active glass. "Down" is away from the
 * active side, i.e. towards the bottom of the screen; the floor is the far
 * wall of the central square. Blocks lying in the three other arms are
 * outside the active glass and never move.
 *
 * Mutates `board` and returns what moved. With `aboveCleared` only the
 * blocks above a cell listed in `cleared` (board indices) are released. */
export function settle(
  board: Board,
  active: Side,
  scope: GravityScope = 'wholeGlass',
  cleared?: ReadonlySet<number>,
): BlockMove[] {
  const glass = new GlassView(board, active);
  const depth = glass.depth;

  // Lowest released row per lane.
  const startRow = new Array<number>(glass.lanes).fill(depth - 1);
  if (scope === 'aboveCleared') {
    startRow.fill(-1);
    for (const index of cleared ?? []) {
      const local = glass.fromWorld(Math.floor(index / board.size), index % board.size);
      if (local === null) continue; // popped in another glass's arm
      if (local.row - 1 > startRow[local.lane]) startRow[local.lane] = local.row - 1;
    }
  }

  const moves: BlockMove[] = [];
  for (let lane = 0; lane < glass.lanes; lane++) {
    for (let row = startRow[lane]; row >= 0; row--) {
      const color = glass.at(row, lane);
      if (color === EMPTY) continue;
      let target = row;
      while (target + 1 < depth && glass.at(target + 1, lane) === EMPTY) target++;
      if (target === row) continue;
      glass.set(row, lane, EMPTY);
      glass.set(target, lane, color);
      moves.push({
        from: glass.toWorld(row, lane),
        to: glass.toWorld(target, lane),
        color: color as BlockColor,
        distance: target - row,
      });
    }
  }
  return moves;
}
