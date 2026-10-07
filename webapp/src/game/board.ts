import { COLOR_SYMBOLS, type BlockColor } from './piece';

/** Value of an empty cell. */
export const EMPTY = -1;

/** The whole cross of settled blocks: the central square and the four arms
 * around it, stored in a square grid in the fixed world frame. The four
 * corner squares of that grid are outside the cross and always empty.
 * Turning the view never touches this data. */
export class Board {
  /** Side of the enclosing grid. */
  readonly size: number;
  private readonly cells: Int8Array;

  constructor(
    /** Side of the central square. */
    readonly center = 10,
    /** Length of each arm. */
    readonly arm = 9,
  ) {
    this.size = center + 2 * arm;
    this.cells = new Int8Array(this.size * this.size).fill(EMPTY);
  }

  /** Index of a cell, used as its identity in sets. */
  index(row: number, col: number): number {
    return row * this.size + col;
  }

  private inCentralBand(i: number): boolean {
    return i >= this.arm && i < this.arm + this.center;
  }

  /** Whether the cell belongs to the cross. */
  isInside(row: number, col: number): boolean {
    if (row < 0 || row >= this.size || col < 0 || col >= this.size) return false;
    return this.inCentralBand(row) || this.inCentralBand(col);
  }

  /** Whether the cell belongs to the central square. */
  isCenter(row: number, col: number): boolean {
    return this.inCentralBand(row) && this.inCentralBand(col);
  }

  /** The colour at a cell, or `EMPTY`. */
  at(row: number, col: number): number {
    return this.cells[row * this.size + col];
  }

  atIndex(index: number): number {
    return this.cells[index];
  }

  set(row: number, col: number, color: number): void {
    this.cells[row * this.size + col] = color;
  }

  isFree(row: number, col: number): boolean {
    return this.isInside(row, col) && this.at(row, col) === EMPTY;
  }

  get blockCount(): number {
    let count = 0;
    for (const cell of this.cells) if (cell !== EMPTY) count++;
    return count;
  }

  get isEmpty(): boolean {
    return this.blockCount === 0;
  }

  /** Calls `visit` for every settled block. */
  forEachBlock(visit: (row: number, col: number, color: BlockColor) => void): void {
    for (let row = 0; row < this.size; row++) {
      for (let col = 0; col < this.size; col++) {
        const color = this.cells[row * this.size + col];
        if (color !== EMPTY) visit(row, col, color as BlockColor);
      }
    }
  }

  clone(): Board {
    const other = new Board(this.center, this.arm);
    other.cells.set(this.cells);
    return other;
  }

  equals(other: Board): boolean {
    if (other.size !== this.size || other.arm !== this.arm) return false;
    return this.cells.every((cell, i) => cell === other.cells[i]);
  }

  /** Fills the central square from text rows such as `'R R . B'`. Rows are
   * aligned to its bottom and columns to its left. `.` is an empty cell;
   * spaces are ignored. */
  paintCenter(rows: readonly string[]): this {
    const firstRow = this.arm + this.center - rows.length;
    rows.forEach((text, i) => {
      const symbols = text.replaceAll(' ', '');
      for (let col = 0; col < symbols.length; col++) {
        const color = (COLOR_SYMBOLS as readonly string[]).indexOf(symbols[col]);
        this.set(firstRow + i, this.arm + col, color);
      }
    });
    return this;
  }

  /** The central square as text, top row first. */
  centerRows(): string[] {
    const rows: string[] = [];
    for (let row = this.arm; row < this.arm + this.center; row++) {
      const symbols: string[] = [];
      for (let col = this.arm; col < this.arm + this.center; col++) {
        const color = this.at(row, col);
        symbols.push(color === EMPTY ? '.' : COLOR_SYMBOLS[color]);
      }
      rows.push(symbols.join(' '));
    }
    return rows;
  }
}
