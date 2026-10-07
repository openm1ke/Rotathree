import { EMPTY, type Board } from './board';
import type { BlockColor } from './piece';

/** One straight line of same-coloured cells. */
export interface MatchRun {
  color: BlockColor;
  /** Board indices of the cells, in order along the line. */
  cells: number[];
  horizontal: boolean;
}

export interface MatchResult {
  runs: MatchRun[];
  /** Union of all matched cells; a cell shared by two lines appears once. */
  cells: Set<number>;
}

/** Finds horizontal and vertical lines of `minLength`+ cells of one colour
 * anywhere on the cross — in the central square, in an arm, or across the
 * border between them. Diagonals do not count. Works in world coordinates:
 * a line is a line whichever way the cross is turned. */
export function findMatches(board: Board, minLength = 3): MatchResult {
  const runs: MatchRun[] = [];
  const n = board.size;

  const scan = (horizontal: boolean, line: number) => {
    const cell = (k: number) => (horizontal ? board.index(line, k) : board.index(k, line));
    let start = 0;
    while (start < n) {
      // Cells outside the cross are always empty, so they end a line too.
      const color = board.atIndex(cell(start));
      let end = start + 1;
      if (color !== EMPTY) {
        while (end < n && board.atIndex(cell(end)) === color) end++;
        if (end - start >= minLength) {
          const cells: number[] = [];
          for (let k = start; k < end; k++) cells.push(cell(k));
          runs.push({ color: color as BlockColor, cells, horizontal });
        }
      }
      start = end;
    }
  };

  for (let i = 0; i < n; i++) {
    scan(true, i);
    scan(false, i);
  }
  return { runs, cells: new Set(runs.flatMap((run) => run.cells)) };
}
