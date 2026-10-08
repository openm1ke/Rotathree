import type { Board } from './board';
import { GlassView, glassIsFree } from './glass';
import { pieceOffsets, type BlockColor, type Piece } from './piece';
import type { Side } from './side';

/** A coloured block at a world position. */
export interface PlacedCell {
  row: number;
  col: number;
  color: BlockColor;
}

/** Where a piece comes to rest. */
export interface Placement {
  side: Side;
  piece: Piece;
  /** Leftmost lane, in the glass of `side`. */
  column: number;
  /** Row of the piece's top square, in the glass of `side`. */
  row: number;
  /** The squares in world coordinates, in the piece's colour order. */
  cells: PlacedCell[];
}

/** Whether `piece` can occupy row `row` at `column` of the glass of `side`.
 *
 * A piece of side S lives in the glass of S: it enters at the far end of the
 * arm of S and moves away from it, through the arm and on through the
 * central square, until the next step would hit the floor or a block. */
export function fits(board: Board, side: Side, piece: Piece, row: number, column: number): boolean {
  // Which square holds which colour does not matter here, only the cells the
  // stick covers: a lying stick runs along its row, a standing one down its lane.
  const length = piece.colors.length;
  if (piece.orientation % 2 === 0) {
    for (let i = 0; i < length; i++) if (!glassIsFree(board, side, row, column + i)) return false;
  } else {
    for (let i = 0; i < length; i++) if (!glassIsFree(board, side, row + i, column)) return false;
  }
  return true;
}

/** The row where `piece`, falling straight down from `fromRow`, comes to
 * rest. Null when it does not even fit at `fromRow`. */
export function landingRow(
  board: Board,
  side: Side,
  piece: Piece,
  column: number,
  fromRow = 0,
): number | null {
  if (!fits(board, side, piece, fromRow, column)) return null;
  let row = fromRow;
  while (fits(board, side, piece, row + 1, column)) row++;
  return row;
}

/** The piece locked at `row`, `column` of its glass. */
export function placementAt(
  board: Board,
  side: Side,
  piece: Piece,
  column: number,
  row: number,
): Placement {
  const glass = new GlassView(board, side);
  const offsets = pieceOffsets(piece);
  return {
    side,
    piece,
    column,
    row,
    cells: piece.colors.map((color, i) => ({
      ...glass.toWorld(row + offsets[i].row, column + offsets[i].col),
      color,
    })),
  };
}

/** Drops `piece` straight down from `fromRow`; null when it has no room. */
export function computeDrop(
  board: Board,
  side: Side,
  piece: Piece,
  column: number,
  fromRow = 0,
): Placement | null {
  const row = landingRow(board, side, piece, column, fromRow);
  return row === null ? null : placementAt(board, side, piece, column, row);
}

/** Free rows at the far end of the glass of `side` in lanes `column` ..
 * `column + width - 1`: how much room a piece appearing there has. */
export function headroom(board: Board, side: Side, column: number, width: number): number {
  const glass = new GlassView(board, side);
  let free = glass.depth;
  for (let lane = column; lane < column + width; lane++) {
    let row = 0;
    while (row < glass.depth && glass.isFree(row, lane)) row++;
    if (row < free) free = row;
  }
  return free;
}
