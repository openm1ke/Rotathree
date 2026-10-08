/** Block colours: red, blue, yellow, green, purple, white. The first
 * `config.numberOfColors` of them are in play. */
export type BlockColor = 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8;

export const COLOR_SYMBOLS = ['R', 'B', 'Y', 'G', 'P', 'W', 'O', 'C', 'K'] as const;

/** The most colours a game can have. */
export const MAX_COLORS = COLOR_SYMBOLS.length;

/** The four ways a stick can lie, in the order a clockwise quarter turn
 * visits them, named by where its *first* colour ends up:
 * 0 — lying, first colour on the left; 1 — standing, first colour on top;
 * 2 — lying, first colour on the right; 3 — standing, first colour at the
 * bottom. */
export type Orientation = 0 | 1 | 2 | 3;

/** A straight stick of coloured squares. The colour order is fixed at
 * creation and the squares can never be rearranged; the stick can only be
 * turned as a whole, a quarter turn at a time. */
export interface Piece {
  readonly colors: readonly BlockColor[];
  readonly orientation: Orientation;
}

export const makePiece = (colors: readonly BlockColor[], orientation: Orientation = 0): Piece => ({
  colors: [...colors],
  orientation,
});

export const isHorizontal = (piece: Piece): boolean => piece.orientation % 2 === 0;

/** Cells taken across the glass. */
export const pieceWidth = (piece: Piece): number => (isHorizontal(piece) ? piece.colors.length : 1);

/** Cells taken along the direction of travel. */
export const pieceDepth = (piece: Piece): number => (isHorizontal(piece) ? 1 : piece.colors.length);

/** The stick after a quarter turn. */
export const rotatePiece = (piece: Piece, clockwise = true): Piece => ({
  colors: piece.colors,
  orientation: ((piece.orientation + (clockwise ? 1 : 3)) % 4) as Orientation,
});

/** Offset of each square from the piece's top-left cell, in colour order. */
export function pieceOffsets(piece: Piece): { row: number; col: number }[] {
  const n = piece.colors.length;
  const flipped = piece.orientation >= 2;
  const lying = isHorizontal(piece);
  return piece.colors.map((_, i) => {
    const along = flipped ? n - 1 - i : i;
    return lying ? { row: 0, col: along } : { row: along, col: 0 };
  });
}

export const samePiece = (a: Piece, b: Piece): boolean =>
  a.orientation === b.orientation &&
  a.colors.length === b.colors.length &&
  a.colors.every((color, i) => color === b.colors[i]);
