import { Board } from '../game/board';
import { defaultConfig, type GameConfig } from '../game/config';
import { GameEngine, type GamePhase } from '../game/engine';
import { makePiece, type BlockColor, type Piece } from '../game/piece';

export const R: BlockColor = 0;
export const B: BlockColor = 1;
export const Y: BlockColor = 2;
export const G: BlockColor = 3;

/** Length of an arm in the test boards: the central square starts here. */
export const ARM = 6;
/** Rows of a test glass (arm + centre); its floor is row `DEPTH - 1`. */
export const DEPTH = 16;

/** Arms of six cells, all four pieces start at the far end; the active
 * piece steps once a second, the others every three. */
export const testConfig: GameConfig = {
  ...defaultConfig,
  armLength: ARM,
  initialProgressStagger: 0,
  activeStepSeconds: 1,
  inactiveStepSeconds: 3,
  seed: 7,
};

/** A stick lying across the glass, first colour on the left. */
export const lying = (colors: BlockColor[]): Piece => makePiece(colors, 0);
/** A stick standing along the direction of travel, first colour on top. */
export const standing = (colors: BlockColor[]): Piece => makePiece(colors, 1);

export const emptyBoard = (): Board => new Board(10, ARM);
export const boardOf = (rows: string[]): Board => emptyBoard().paintCenter(rows);

/** Colour of a cell of the central square (row 0 on top). */
export const centerAt = (board: Board, row: number, col: number): number =>
  board.at(ARM + row, ARM + col);

export function newEngine(overrides: Partial<GameConfig> = {}, center: string[] = []): GameEngine {
  const engine = new GameEngine({ ...testConfig, ...overrides });
  if (center.length > 0) engine.board.paintCenter(center);
  return engine;
}

/** Runs the timed phases (drop flight, flash, pop, fall) to their end and
 * returns every phase passed through. */
export function runUntilPlaying(engine: GameEngine): GamePhase[] {
  const phases: GamePhase[] = [engine.phase];
  let guard = 0;
  while (engine.phase !== 'playing' && !engine.isGameOver) {
    engine.update(0.002);
    if (engine.phase !== phases[phases.length - 1]) phases.push(engine.phase);
    if (++guard > 200000) throw new Error('engine never returned to playing');
  }
  return phases;
}
