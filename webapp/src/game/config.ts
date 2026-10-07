import { LEFT, RIGHT, SIDES, TOP, type Side } from './side';

/** Which blocks fall after a match has popped. */
export type GravityScope =
  /** Every unsupported block of the active glass falls to rest. */
  | 'wholeGlass'
  /** Only the blocks sitting above a popped cell fall. */
  | 'aboveCleared';

/** Every tunable of the game lives here. Same meaning as the Flutter
 * `GameConfig`. */
export interface GameConfig {
  /** Side of the central square, and the width of each of the four glasses. */
  boardSize: number;
  /** Length of each outer arm, in cells. A glass is one arm plus the centre. */
  armLength: number;
  /** How many of the four glasses are in play, 2 to 4: the one the game
   * starts in plus one to three more. The arms of the others do not exist. */
  glassCount: number;
  /** Number of squares in a stick. */
  pieceLength: number;
  /** How many colours are in play, 3 to 6. */
  numberOfColors: number;
  /** Shortest line of one colour that counts as a match. */
  minMatchLength: number;
  /** Pieces fall one whole cell at a time. In the active glass a step comes
   * this often… */
  activeStepSeconds: number;
  /** …and in the three other glasses this often. A piece that cannot take
   * its next step locks instead. */
  inactiveStepSeconds: number;
  /** While soft drop is held, the active piece steps this often as long as
   * it has room to fall. */
  softDropStepSeconds: number;
  /** Head start, as a fraction of the arm, between the four pieces at the
   * beginning of a game. */
  initialProgressStagger: number;
  /** Lane where a new piece appears; null centres it. */
  spawnColumn: number | null;
  /** A single-colour stick is kept with this probability; otherwise one of
   * its squares is repainted. */
  monoPieceKeepChance: number;
  /** Let the blocks of the new active glass fall on every turn. */
  settleAfterBoardRotation: boolean;
  /** Freeze all falling pieces while a match is being resolved. */
  pauseIncomingDuringCascade: boolean;
  gravityScope: GravityScope;
  /** A glass with this many free rows or fewer at its far end is flagged. */
  crowdedHeadroom: number;
  dropBaseSeconds: number;
  dropSecondsPerCell: number;
  /** Matched cells flash for this long… */
  matchSeconds: number;
  /** …then pop for this long. */
  clearSeconds: number;
  /** Falling `n` cells takes `fallBaseSeconds + fallSecondsPerRootCell·√n`. */
  fallBaseSeconds: number;
  fallSecondsPerRootCell: number;
  /** A block that has landed wobbles for this long before play goes on. */
  fallBounceSeconds: number;
  /** Inputs received while the board resolves are replayed afterwards. */
  maxQueuedInputs: number;
  /** Points for the shortest possible match. */
  basePoints: number;
  /** Seed for the piece generator; null = non-deterministic. */
  seed: number | null;
}

export const defaultConfig: GameConfig = {
  boardSize: 10,
  armLength: 9,
  glassCount: 4,
  pieceLength: 3,
  numberOfColors: 3,
  minMatchLength: 3,
  activeStepSeconds: 1,
  inactiveStepSeconds: 3,
  softDropStepSeconds: 0.05,
  initialProgressStagger: 0.15,
  spawnColumn: null,
  monoPieceKeepChance: 0.4,
  settleAfterBoardRotation: false,
  pauseIncomingDuringCascade: true,
  gravityScope: 'wholeGlass',
  crowdedHeadroom: 2,
  dropBaseSeconds: 0.06,
  dropSecondsPerCell: 0.008,
  matchSeconds: 0.16,
  clearSeconds: 0.2,
  fallBaseSeconds: 0.09,
  fallSecondsPerRootCell: 0.1,
  fallBounceSeconds: 0.12,
  maxQueuedInputs: 8,
  basePoints: 100,
  seed: null,
};

/** The glasses in play. Two are neighbours, so that switching is a quarter
 * turn; three leave out the one opposite the starting glass. */
export const sidesInPlay = (c: GameConfig): readonly Side[] =>
  c.glassCount <= 2 ? [TOP, RIGHT] : c.glassCount === 3 ? [TOP, RIGHT, LEFT] : SIDES;

/** Rows of one glass, from the far end of its arm to its floor. */
export const glassDepth = (c: GameConfig): number => c.armLength + c.boardSize;

/** Side of the square grid that contains the whole cross. */
export const gridSize = (c: GameConfig): number => c.boardSize + 2 * c.armLength;

export const spawnColumnOf = (c: GameConfig): number =>
  c.spawnColumn ?? Math.floor((c.boardSize - c.pieceLength) / 2);

/** Flight time of a hard drop over `cells` cells. */
export const dropSeconds = (c: GameConfig, cells: number): number =>
  c.dropBaseSeconds + c.dropSecondsPerCell * cells;

/** Time a released block needs to fall `cells` cells. */
export const fallSeconds = (c: GameConfig, cells: number): number =>
  c.fallBaseSeconds + c.fallSecondsPerRootCell * Math.sqrt(cells);

/** Length of the falling phase: the furthest flight plus the wobble. */
export const fallPhaseSeconds = (c: GameConfig, cells: number): number =>
  fallSeconds(c, cells) + c.fallBounceSeconds;

/** Value of one matched line at the given combo level (1 = first match):
 * 3 → 100, 4 → 200, 5 → 300 … times the combo. */
export const scoreForRun = (c: GameConfig, runLength: number, combo: number): number =>
  runLength < c.minMatchLength
    ? 0
    : c.basePoints * (runLength - c.minMatchLength + 1) * combo;
