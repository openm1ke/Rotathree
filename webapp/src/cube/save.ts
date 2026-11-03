// A game of Cube kept between visits, as the flat game keeps its runs
// (services/runSave.ts): taken while the game is at rest, so that it comes
// back exactly as it was left.
import { integer, record } from '../game/snapshotReader';
import type { RunRecord } from '../services/storage';
import { CubeGame, type CubeSnapshot } from './rules';

export interface CubeSave {
  version: 1;
  /** The run's id, kept for its record in the statistics. */
  id: string;
  savedAt: number;
  game: CubeSnapshot;
}

export function sanitizeCubeSave(raw: unknown): CubeSave | null {
  if (raw == null) return null;
  try {
    const r = record(raw);
    if (r.version !== 1 || typeof r.id !== 'string' || r.id.length === 0 || r.id.length > 80) return null;
    // Whatever restores is a game; anything else is dropped.
    CubeGame.restore(r.game);
    return { version: 1, id: r.id, savedAt: integer(r.savedAt, 0, Number.MAX_SAFE_INTEGER), game: r.game as CubeSnapshot };
  } catch {
    return null;
  }
}

/** The record of a kept game given up: a new one was started instead. */
export function abandonedCube(save: CubeSave): RunRecord {
  const game = CubeGame.restore(save.game);
  return {
    id: save.id,
    mode: 'cube',
    at: Date.now(),
    score: game.score,
    pieces: game.placed,
    matches: game.matches,
    bestCombo: game.bestCombo,
    seconds: game.seconds,
    level: game.speedLevel + 1,
    completed: false,
    interrupted: true,
  };
}
