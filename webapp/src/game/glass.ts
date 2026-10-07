import type { Board } from './board';
import { EMPTY } from './board';
import type { Side } from './side';

export interface Cell {
  row: number;
  col: number;
}

/** Maps a cell of the *view* frame of `side` — the frame in which that
 * side's glass is on top and its pieces fall straight down — to the fixed
 * world frame. The board data never rotates; turning the cross only changes
 * which side's frame is used to read it. */
export function viewToWorld(row: number, col: number, side: Side, size: number): Cell {
  const last = size - 1;
  switch (side) {
    case 0:
      return { row, col };
    case 1:
      return { row: col, col: last - row };
    case 2:
      return { row: last - row, col: last - col };
    default:
      return { row: last - col, col: row };
  }
}

export function worldToView(row: number, col: number, side: Side, size: number): Cell {
  const last = size - 1;
  switch (side) {
    case 0:
      return { row, col };
    case 1:
      return { row: last - col, col: row };
    case 2:
      return { row: last - row, col: last - col };
    default:
      return { row: col, col: last - row };
  }
}

/** The world side whose glass is drawn in screen slot `slot` while `active`
 * is on top. */
export const sideAtSlot = (active: Side, slot: Side): Side => ((active + slot) % 4) as Side;

/** The screen slot in which the glass of `worldSide` is drawn. */
export const slotOfSide = (active: Side, worldSide: Side): Side =>
  ((((worldSide - active) % 4) + 4) % 4) as Side;

/** One glass: the arm of `side` plus the central square, seen with that
 * side on top. Row 0 is the far end of the arm, the last row is the floor —
 * the far wall of the central square. Lanes run across the glass.
 *
 * The four glasses share the central square; each also owns its own arm. */
export class GlassView {
  constructor(
    readonly board: Board,
    readonly side: Side,
  ) {}

  /** Width of the glass. */
  get lanes(): number {
    return this.board.center;
  }

  /** Number of rows from the far end of the arm to the floor. */
  get depth(): number {
    return this.board.arm + this.board.center;
  }

  toWorld(row: number, lane: number): Cell {
    return viewToWorld(row, this.board.arm + lane, this.side, this.board.size);
  }

  /** The (row, lane) of a world cell in this glass, or null if the cell is
   * in another glass's arm. */
  fromWorld(row: number, col: number): { row: number; lane: number } | null {
    const view = worldToView(row, col, this.side, this.board.size);
    const lane = view.col - this.board.arm;
    if (lane < 0 || lane >= this.lanes || view.row < 0 || view.row >= this.depth) return null;
    return { row: view.row, lane };
  }

  contains(row: number, lane: number): boolean {
    return row >= 0 && row < this.depth && lane >= 0 && lane < this.lanes;
  }

  at(row: number, lane: number): number {
    const world = this.toWorld(row, lane);
    return this.board.at(world.row, world.col);
  }

  set(row: number, lane: number, color: number): void {
    const world = this.toWorld(row, lane);
    this.board.set(world.row, world.col, color);
  }

  isFree(row: number, lane: number): boolean {
    return this.contains(row, lane) && this.at(row, lane) === EMPTY;
  }
}
