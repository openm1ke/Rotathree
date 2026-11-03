// A game of Cube kept between visits, as the flat game keeps its runs
// (services/runSave.ts): taken while the game is at rest, so that it comes
// back exactly as it was left. One endless game and one campaign level may
// be kept at a time.
import { integer, record } from '../game/snapshotReader';
import type { RunRecord } from '../services/storage';
import { CUBE_CAMPAIGN_LAST } from './campaign';
import { CubeGame, type CubeSnapshot } from './rules';

export interface CubeSave {
  version: 1;
  /** The run's id, kept for its record in the statistics. */
  id: string;
  savedAt: number;
  game: CubeSnapshot;
  /** The campaign level, by index; absent for the endless game. */
  level?: number;
}

export type CubeKind = 'endless' | 'campaign';
export type CubeRuns = Partial<Record<CubeKind, CubeSave>>;

export const kindOf = (level: number | null | undefined): CubeKind => (level == null ? 'endless' : 'campaign');

export function sanitizeCubeSave(raw: unknown): CubeSave | null {
  if (raw == null) return null;
  try {
    const r = record(raw);
    if (r.version !== 1 || typeof r.id !== 'string' || r.id.length === 0 || r.id.length > 80) return null;
    // Whatever restores is a game; anything else is dropped.
    CubeGame.restore(r.game);
    const save: CubeSave = { version: 1, id: r.id, savedAt: integer(r.savedAt, 0, Number.MAX_SAFE_INTEGER), game: r.game as CubeSnapshot };
    if (r.level !== undefined) save.level = integer(r.level, 0, CUBE_CAMPAIGN_LAST);
    return save;
  } catch {
    return null;
  }
}

/** Both slots; a single save, as the first version kept, is the endless one. */
export function sanitizeCubeRuns(raw: unknown): CubeRuns {
  const single = sanitizeCubeSave(raw);
  if (single) return single.level === undefined ? { endless: single } : { campaign: single };
  if (typeof raw !== 'object' || raw === null) return {};
  const r = raw as Record<string, unknown>;
  if (r.version !== 2 || typeof r.runs !== 'object' || r.runs === null) return {};
  const runs = r.runs as Record<string, unknown>;
  const result: CubeRuns = {};
  const endless = sanitizeCubeSave(runs.endless);
  const campaign = sanitizeCubeSave(runs.campaign);
  if (endless && endless.level === undefined) result.endless = endless;
  if (campaign && campaign.level !== undefined) result.campaign = campaign;
  return result;
}

/** The record of a kept game given up: a new one was started instead. */
export function abandonedCube(save: CubeSave): RunRecord {
  const game = CubeGame.restore(save.game);
  return {
    id: save.id,
    mode: save.level === undefined ? 'cube' : 'cubeCampaign',
    at: Date.now(),
    score: game.score,
    pieces: game.placed,
    matches: game.matches,
    bestCombo: game.bestCombo,
    seconds: game.seconds,
    level: save.level === undefined ? game.speedLevel + 1 : save.level + 1,
    completed: false,
    interrupted: true,
  };
}
