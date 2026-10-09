import { CAMPAIGN_LAST } from '../game/campaign';
import { GameEngine } from '../game/engine';
import { sanitizeCustom } from '../game/modes';
import { planFor, type Session } from '../game/session';
import { integer, number, record } from '../game/snapshotReader';
import type { RunRecord } from './storage';

export interface RunTotals {
  score: number;
  pieces: number;
  matches: number;
  bestCombo: number;
  seconds: number;
}
export interface SavedBanner {
  kicker: string;
  title: string;
  sub?: string;
  left: number;
  blocking: boolean;
  pendingLevel: number | null;
  colours: number;
}
export interface RunSave {
  version: 1;
  id: string;
  session: Session;
  engine: Record<string, unknown>;
  carry: RunTotals;
  levelBase: number;
  savedAt: number;
  banner: SavedBanner | null;
}

export function sanitizeRunSave(raw: unknown): RunSave | null {
  if (raw == null) return null;
  try {
    const r = record(raw),
      s = record(r.session);
    if (r.version !== 1 || typeof r.id !== 'string' || r.id.length === 0 || r.id.length > 80) return null;
    const session: Session =
      s.mode === 'campaign'
        ? { mode: 'campaign', level: integer(s.level, 0, CAMPAIGN_LAST) }
        : s.mode === 'insane'
          ? { mode: 'insane' }
          : s.mode === 'custom'
            ? { mode: 'custom', setup: sanitizeCustom(s.setup) }
            : (() => {
                throw new Error('Invalid session');
              })();
    const engine = record(r.engine),
      plan = planFor(session),
      check = new GameEngine(plan.config);
    check.setRamp(plan.ramp);
    check.restoreSnapshot(engine);
    const t = record(r.carry);
    const carry = {
      score: integer(t.score),
      pieces: integer(t.pieces),
      matches: integer(t.matches),
      bestCombo: integer(t.bestCombo),
      seconds: number(t.seconds),
    };
    const levelBase = integer(r.levelBase, 0, check.state.score);
    let banner: SavedBanner | null = null;
    if (r.banner !== null) {
      const b = record(r.banner);
      if (
        typeof b.kicker !== 'string' ||
        typeof b.title !== 'string' ||
        typeof b.blocking !== 'boolean' ||
        (b.sub !== undefined && typeof b.sub !== 'string')
      )
        return null;
      banner = {
        kicker: b.kicker,
        title: b.title,
        sub: b.sub as string | undefined,
        blocking: b.blocking,
        left: number(b.left, 0, 10),
        pendingLevel: b.pendingLevel === null ? null : integer(b.pendingLevel, 0, CAMPAIGN_LAST),
        colours: integer(b.colours, 0, 9),
      };
      if (banner.pendingLevel !== null && (session.mode !== 'campaign' || banner.pendingLevel !== session.level + 1))
        return null;
    }
    return {
      version: 1,
      id: r.id,
      session,
      engine,
      carry,
      levelBase,
      savedAt: integer(r.savedAt, 0, Number.MAX_SAFE_INTEGER),
      banner,
    };
  } catch {
    return null;
  }
}

export function abandonedRun(save: RunSave): RunRecord {
  const e = save.engine,
    t = save.carry;
  return {
    id: save.id,
    mode: save.session.mode,
    at: Date.now(),
    score: t.score + (e.score as number),
    pieces: t.pieces + (e.piecesPlaced as number),
    matches: t.matches + (e.matches as number),
    bestCombo: Math.max(t.bestCombo, e.bestCombo as number),
    seconds: t.seconds + (e.elapsedSeconds as number),
    level: save.session.mode === 'campaign' ? save.session.level + 1 : (e.speedLevel as number) + 1,
    completed: false,
    interrupted: true,
  };
}

/** Independent resumable slots; version 1's single save migrates in place. */
export type SavedRuns = Partial<Record<Session['mode'], RunSave>>;
export function sanitizeSavedRuns(raw: unknown): SavedRuns {
  const legacy = sanitizeRunSave(raw);
  if (legacy) return { [legacy.session.mode]: legacy };
  if (typeof raw !== 'object' || raw === null) return {};
  const envelope = raw as Record<string, unknown>;
  if (envelope.version !== 2 || typeof envelope.runs !== 'object' || envelope.runs === null) return {};
  const runs = envelope.runs as Record<string, unknown>;
  const result: SavedRuns = {};
  for (const mode of ['campaign', 'custom', 'insane'] as const) {
    const save = sanitizeRunSave(runs[mode]);
    if (save?.session.mode === mode) result[mode] = save;
  }
  return result;
}
