import { EMPTY, type Board } from './board';
import { scoreForRun, type GameConfig } from './config';
import { settle, type BlockMove } from './gravity';
import { findMatches, type MatchResult } from './matchDetector';
import type { Side } from './side';

/** One round of a cascade: what matched, what it scored and what fell. */
export interface CascadeStep {
  /** 1 for the match made by the placement itself, 2 for the first cascade… */
  combo: number;
  match: MatchResult;
  score: number;
  moves: BlockMove[];
}

export const scoreFor = (config: GameConfig, match: MatchResult, combo: number): number =>
  match.runs.reduce((sum, run) => sum + scoreForRun(config, run.cells.length, combo), 0);

export function clearMatch(board: Board, match: MatchResult): void {
  for (const index of match.cells) {
    board.set(Math.floor(index / board.size), index % board.size, EMPTY);
  }
}

/** Runs match → pop → fall rounds until the board is stable. Mutates
 * `board`. The engine walks through the same primitives one animated phase
 * at a time; this runs the whole loop at once (tests). */
export function resolveCascade(board: Board, active: Side, config: GameConfig): CascadeStep[] {
  const steps: CascadeStep[] = [];
  for (;;) {
    const match = findMatches(board, config.minMatchLength);
    if (match.runs.length === 0) return steps;
    const combo = steps.length + 1;
    const score = scoreFor(config, match, combo);
    clearMatch(board, match);
    const moves = settle(board, active, config.gravityScope, match.cells);
    steps.push({ combo, match, score, moves });
  }
}
