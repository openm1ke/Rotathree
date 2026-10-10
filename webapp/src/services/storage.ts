import { languageChoice, type LanguageChoice } from '../i18n/catalog';
import { DEFAULT_COLOURS, COLOUR_NAMES } from '../render/theme';
import { defaultBindings, cloneBindings, sanitizeBindings, type Bindings } from '../input/bindings';
import { defaultHandling, type Handling } from '../input/keyboard';
import { CAMPAIGN } from '../game/campaign';
import { DEFAULT_CUSTOM, sanitizeCustom, type CustomSetup, type ModeId } from '../game/modes';
import { sanitizeRunSave, sanitizeSavedRuns, type RunSave, type SavedRuns } from './runSave';
import { DEFAULT_PADS, PAD_SLOTS, type PadLayout } from '../input/pads';
import { DEFAULT_POSITIONS, sanitizePositions, type PadPositions } from '../input/padPlacement';
import { ACTIONS } from '../input/bindings';
import { getPlatformStorage } from '../platform/storageBackend';

/** How the explosion of a match looks: one animation for everything, or one
 * per kind of match. */
export type ExplosionStyle = 'unified' | 'varied';

export interface HudOptions {
  /** The reminder of which key does what. */
  keyHints: boolean;
  /** The score, the level and the combo callouts. */
  score: boolean;
  /** Time, pieces, matches, best combo. */
  stats: boolean;
  /** Opacity of the writing on the field, 0.1 … 1. */
  opacity: number;
}

export interface PaletteSet {
  id: string;
  name: string;
  /** One colour per colour slot, in the order of COLOUR_NAMES. */
  colours: string[];
  /** Built-in sets cannot be changed; editing one copies it first. */
  builtin: boolean;
}

export interface Palettes {
  active: string;
  sets: PaletteSet[];
}

export interface Effects {
  explosion: ExplosionStyle;
  screenShake: boolean;
  /** Milliseconds the cross takes to turn a quarter; 0 turns it at once. */
  turnMs: number;
}

export interface AudioOptions {
  music: boolean;
  /** Master volume from 0 to 1. */
  musicVolume: number;
}

export interface Settings {
  language: LanguageChoice;
  bindings: Bindings;
  handling: Handling;
  palettes: Palettes;
  effects: Effects;
  hud: HudOptions;
  pads: { left: PadLayout; right: PadLayout };
  padPositions: PadPositions;
  audio: AudioOptions;
}

export const BUILTIN_PALETTES: PaletteSet[] = [
  { id: 'classic', name: 'Классика', colours: [...DEFAULT_COLOURS], builtin: true },
  {
    id: 'pastel',
    name: 'Пастель',
    colours: ['#ff8fa3', '#8fc1ff', '#ffe08a', '#9ff0c4', '#c9a8ff', '#f4f6fb', '#ffb88a', '#9ff4fa', '#ffb3dc'],
    builtin: true,
  },
  {
    id: 'neon',
    name: 'Неон',
    colours: ['#ff2d6f', '#1e90ff', '#ffe600', '#00ff9c', '#b200ff', '#ffffff', '#ff7a00', '#00e5ff', '#ff00c8'],
    builtin: true,
  },
];

export const defaultSettings = (): Settings => ({
  language: 'auto',
  bindings: cloneBindings(defaultBindings),
  handling: { ...defaultHandling },
  palettes: { active: 'classic', sets: BUILTIN_PALETTES.map((set) => ({ ...set, colours: [...set.colours] })) },
  effects: { explosion: 'varied', screenShake: true, turnMs: 260 },
  hud: { keyHints: true, score: true, stats: true, opacity: 1 },
  pads: { left: { ...DEFAULT_PADS.left }, right: { ...DEFAULT_PADS.right } },
  padPositions: structuredClone(DEFAULT_POSITIONS),
  audio: { music: true, musicVolume: 0.1 },
});

const HEX = /^#[0-9a-f]{6}$/i;

const numberIn = (value: unknown, min: number, max: number, fallback: number): number =>
  typeof value === 'number' && Number.isFinite(value) ? Math.min(max, Math.max(min, value)) : fallback;

function sanitizePalettes(raw: unknown): Palettes {
  const base = defaultSettings().palettes;
  if (typeof raw !== 'object' || raw === null) return base;
  const stored = raw as Record<string, unknown>;
  const custom: PaletteSet[] = [];
  if (Array.isArray(stored.sets)) {
    for (const item of stored.sets) {
      if (typeof item !== 'object' || item === null) continue;
      const set = item as Record<string, unknown>;
      if (typeof set.id !== 'string' || typeof set.name !== 'string' || !Array.isArray(set.colours)) continue;
      if (set.builtin === true) continue;
      const colours = COLOUR_NAMES.map((_, i) => {
        const value = set.colours as unknown[];
        return typeof value[i] === 'string' && HEX.test(value[i] as string) ? (value[i] as string) : DEFAULT_COLOURS[i];
      });
      custom.push({ id: set.id, name: set.name.slice(0, 24), colours, builtin: false });
    }
  }
  const sets = [...base.sets, ...custom];
  const active =
    typeof stored.active === 'string' && sets.some((set) => set.id === stored.active) ? stored.active : 'classic';
  return { active, sets };
}

/** Makes sense of whatever was stored; anything missing or out of range falls
 * back to its default. */
export function sanitizeSettings(raw: unknown): Settings {
  const base = defaultSettings();
  if (typeof raw !== 'object' || raw === null) return base;
  const stored = raw as Record<string, unknown>;
  const handling = (stored.handling ?? {}) as Record<string, unknown>;
  const effects = (stored.effects ?? {}) as Record<string, unknown>;
  const hud = (stored.hud ?? {}) as Record<string, unknown>;
  const pads = (stored.pads ?? {}) as Record<string, unknown>;
  const audio = (stored.audio ?? {}) as Record<string, unknown>;
  const pad = (raw: unknown, fallback: PadLayout): PadLayout => {
    const p = (typeof raw === 'object' && raw !== null ? raw : {}) as Record<string, unknown>;
    return Object.fromEntries(
      PAD_SLOTS.map((slot) => [
        slot,
        p[slot] === 'none' || ACTIONS.some((a) => a.id === p[slot]) ? p[slot] : fallback[slot],
      ]),
    ) as PadLayout;
  };
  return {
    language: languageChoice(stored.language),
    bindings: sanitizeBindings(stored.bindings),
    padPositions: sanitizePositions(stored.padPositions),
    pads: { left: pad(pads.left, DEFAULT_PADS.left), right: pad(pads.right, DEFAULT_PADS.right) },
    handling: {
      dasMs: numberIn(handling.dasMs, 0, 400, base.handling.dasMs),
      arrMs: numberIn(handling.arrMs, 0, 150, base.handling.arrMs),
    },
    palettes: sanitizePalettes(stored.palettes),
    effects: {
      explosion: effects.explosion === 'unified' ? 'unified' : 'varied',
      screenShake: effects.screenShake !== false,
      turnMs: Math.round(numberIn(effects.turnMs, 0, 800, base.effects.turnMs)),
    },
    hud: {
      keyHints: hud.keyHints !== false,
      score: hud.score !== false,
      stats: hud.stats !== false,
      opacity: numberIn(hud.opacity, 0.1, 1, base.hud.opacity),
    },
    audio: {
      music: audio.music !== false,
      musicVolume: numberIn(audio.musicVolume ?? audio.volume, 0, 1, base.audio.musicVolume),
    },
  };
}

// ----------------------------------------------------------------- progress

/** How far the campaign has been played. */
export interface Progress {
  /** Index of the highest level that is open (0 at the start). */
  unlocked: number;
  /** Whether the last level has been finished, which opens Insane. */
  completed: boolean;
  /** Best score of each level, by index; 0 when never finished. */
  best: number[];
}

export const defaultProgress = (): Progress => ({
  unlocked: 0,
  completed: false,
  best: CAMPAIGN.map(() => 0),
});

export function sanitizeProgress(raw: unknown): Progress {
  const base = defaultProgress();
  if (typeof raw !== 'object' || raw === null) return base;
  const stored = raw as Record<string, unknown>;
  const unlocked = Math.round(numberIn(stored.unlocked, 0, CAMPAIGN.length - 1, 0));
  const best = CAMPAIGN.map((_, i) => {
    const value = Array.isArray(stored.best) ? stored.best[i] : undefined;
    return Math.max(0, Math.round(numberIn(value, 0, 1e9, 0)));
  });
  return { unlocked, completed: stored.completed === true, best: base.best.length ? best : base.best };
}

// -------------------------------------------------------------------- stats

/** One finished run. */
export interface RunRecord {
  id: string;
  mode: ModeId;
  /** Milliseconds since the epoch, when the run ended. */
  at: number;
  score: number;
  pieces: number;
  matches: number;
  bestCombo: number;
  seconds: number;
  /** The campaign level reached, or the speed level + 1 of Insane and Custom. */
  level: number;
  /** Campaign only: whether the last level was finished. */
  completed: boolean;
  interrupted?: boolean;
}

export interface ModeStats {
  games: number;
  completed: number;
  totalScore: number;
  bestScore: number;
  totalPieces: number;
  totalMatches: number;
  bestCombo: number;
  totalSeconds: number;
  bestLevel: number;
}

export interface Stats {
  modes: Record<ModeId, ModeStats>;
  recent: RunRecord[];
}

const emptyModeStats = (): ModeStats => ({
  games: 0,
  completed: 0,
  totalScore: 0,
  bestScore: 0,
  totalPieces: 0,
  totalMatches: 0,
  bestCombo: 0,
  totalSeconds: 0,
  bestLevel: 0,
});

export const defaultStats = (): Stats => ({
  modes: { campaign: emptyModeStats(), insane: emptyModeStats(), custom: emptyModeStats() },
  recent: [],
});

const RECENT_LIMIT = 20;

/** Adds a finished run to the totals and to the list of recent runs. */
export function addRun(stats: Stats, run: RunRecord): Stats {
  if (stats.recent.some((old) => old.id === run.id)) return stats;
  const old = stats.modes[run.mode];
  const next: ModeStats = {
    games: old.games + 1,
    completed: old.completed + (run.completed ? 1 : 0),
    totalScore: old.totalScore + run.score,
    bestScore: Math.max(old.bestScore, run.score),
    totalPieces: old.totalPieces + run.pieces,
    totalMatches: old.totalMatches + run.matches,
    bestCombo: Math.max(old.bestCombo, run.bestCombo),
    totalSeconds: old.totalSeconds + run.seconds,
    bestLevel: Math.max(old.bestLevel, run.level),
  };
  return {
    modes: { ...stats.modes, [run.mode]: next },
    recent: [run, ...stats.recent].slice(0, RECENT_LIMIT),
  };
}

function sanitizeModeStats(raw: unknown): ModeStats {
  const base = emptyModeStats();
  if (typeof raw !== 'object' || raw === null) return base;
  const r = raw as Record<string, unknown>;
  const count = (key: keyof ModeStats) => Math.max(0, Math.round(numberIn(r[key], 0, 1e12, 0)));
  return {
    games: count('games'),
    completed: count('completed'),
    totalScore: count('totalScore'),
    bestScore: count('bestScore'),
    totalPieces: count('totalPieces'),
    totalMatches: count('totalMatches'),
    bestCombo: count('bestCombo'),
    totalSeconds: count('totalSeconds'),
    bestLevel: count('bestLevel'),
  };
}

export function sanitizeStats(raw: unknown): Stats {
  if (typeof raw !== 'object' || raw === null) return defaultStats();
  const r = raw as Record<string, unknown>;
  const modes = (typeof r.modes === 'object' && r.modes !== null ? r.modes : {}) as Record<string, unknown>;
  const recent = Array.isArray(r.recent)
    ? r.recent.flatMap((item): RunRecord[] => {
        if (typeof item !== 'object' || item === null) return [];
        const run = item as Record<string, unknown>;
        if (run.mode !== 'campaign' && run.mode !== 'insane' && run.mode !== 'custom') return [];
        return [
          {
            id: String(run.id ?? ''),
            mode: run.mode,
            at: numberIn(run.at, 0, 1e15, 0),
            score: Math.round(numberIn(run.score, 0, 1e12, 0)),
            pieces: Math.round(numberIn(run.pieces, 0, 1e9, 0)),
            matches: Math.round(numberIn(run.matches, 0, 1e9, 0)),
            bestCombo: Math.round(numberIn(run.bestCombo, 0, 1e6, 0)),
            seconds: numberIn(run.seconds, 0, 1e9, 0),
            level: Math.round(numberIn(run.level, 0, 1e6, 0)),
            completed: run.completed === true,
            interrupted: run.interrupted === true,
          },
        ];
      })
    : [];
  return {
    modes: {
      campaign: sanitizeModeStats(modes.campaign),
      insane: sanitizeModeStats(modes.insane),
      custom: sanitizeModeStats(modes.custom),
    },
    recent: recent.slice(0, RECENT_LIMIT),
  };
}

// ------------------------------------------------------------------ storage

export const STORAGE_KEYS = {
  settings: 'rotathree.settings.v2',
  progress: 'rotathree.progress.v1',
  stats: 'rotathree.stats.v1',
  custom: 'rotathree.custom.v1',
  run: 'rotathree.run.web.v1',
  tutorial: 'rotathree.tutorial.v1',
} as const;
const KEYS = STORAGE_KEYS;

type KeyValue = Partial<Pick<Storage, 'getItem' | 'setItem'>>;

/** `localStorage`, or null where it is unavailable or forbidden. */
export function browserStorage(): KeyValue | null {
  const platform = getPlatformStorage();
  if (platform) return platform;
  try {
    return globalThis.localStorage ?? null;
  } catch {
    return null;
  }
}

function read<T>(key: string, sanitize: (raw: unknown) => T, storage: KeyValue | null): T {
  try {
    const text = storage?.getItem?.(key);
    return sanitize(text ? JSON.parse(text) : undefined);
  } catch {
    return sanitize(undefined);
  }
}

/** Returns whether the value was actually written. */
function write(key: string, value: unknown, storage: KeyValue | null): boolean {
  try {
    if (!storage?.setItem) return false;
    storage.setItem(key, JSON.stringify(value));
    return true;
  } catch {
    return false;
  }
}

export const loadSettings = (storage = browserStorage()) => read(KEYS.settings, sanitizeSettings, storage);
export const saveSettings = (value: Settings, storage = browserStorage()) => write(KEYS.settings, value, storage);
export const loadProgress = (storage = browserStorage()) => read(KEYS.progress, sanitizeProgress, storage);
export const saveProgress = (value: Progress, storage = browserStorage()) => write(KEYS.progress, value, storage);
export const loadStats = (storage = browserStorage()) => read(KEYS.stats, sanitizeStats, storage);
export const saveStats = (value: Stats, storage = browserStorage()) => write(KEYS.stats, value, storage);
export const loadCustom = (storage = browserStorage()): CustomSetup =>
  read(KEYS.custom, (raw) => (raw === undefined ? { ...DEFAULT_CUSTOM } : sanitizeCustom(raw)), storage);
export const saveCustom = (value: CustomSetup, storage = browserStorage()) => write(KEYS.custom, value, storage);
export const loadRun = (storage = browserStorage()) => read(KEYS.run, sanitizeRunSave, storage);
export const saveRun = (value: RunSave | null, storage = browserStorage()) => write(KEYS.run, value, storage);
export const loadRuns = (storage = browserStorage()) => read(KEYS.run, sanitizeSavedRuns, storage);
export const saveRuns = (runs: SavedRuns, storage = browserStorage()) => write(KEYS.run, { version: 2, runs }, storage);
export const loadTutorial = (storage = browserStorage()) => read(KEYS.tutorial, (raw) => raw === true, storage);
export const saveTutorial = (value: boolean, storage = browserStorage()) => write(KEYS.tutorial, value, storage);
