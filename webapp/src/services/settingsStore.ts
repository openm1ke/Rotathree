import type { GameConfig, GravityScope } from '../game/config';
import { defaultConfig } from '../game/config';
import { MAX_COLORS } from '../game/piece';
import { cloneBindings, defaultBindings, sanitizeBindings, type Bindings } from '../input/bindings';
import { defaultHandling, type Handling } from '../input/keyboard';

/** The part of the game configuration the player can change. */
export interface GameOptions {
  activeStepSeconds: number;
  inactiveStepSeconds: number;
  armLength: number;
  /** Glasses in play, 2 to 4: the player's own plus one to three more. */
  glassCount: number;
  numberOfColors: number;
  gravityScope: GravityScope;
  settleAfterBoardRotation: boolean;
}

/** What is written in the corners of the field, and how strongly. */
export interface HudOptions {
  /** The reminder of which key does what. */
  keyHints: boolean;
  /** The score, the level and the combo callouts. */
  score: boolean;
  /** Time, pieces, matches, best combo. */
  stats: boolean;
  /** Opacity of all of the above, 0.1 … 1. */
  opacity: number;
}

export interface Settings {
  bindings: Bindings;
  handling: Handling;
  game: GameOptions;
  hud: HudOptions;
  /** Milliseconds the cross takes to turn a quarter; 0 turns it at once. */
  turnMs: number;
  /** Board kicks and shakes on drops and pops. */
  screenShake: boolean;
}

export const defaultGameOptions: GameOptions = {
  activeStepSeconds: defaultConfig.activeStepSeconds,
  inactiveStepSeconds: defaultConfig.inactiveStepSeconds,
  armLength: defaultConfig.armLength,
  glassCount: defaultConfig.glassCount,
  numberOfColors: defaultConfig.numberOfColors,
  gravityScope: defaultConfig.gravityScope,
  settleAfterBoardRotation: defaultConfig.settleAfterBoardRotation,
};

export const defaultHudOptions: HudOptions = { keyHints: true, score: true, stats: true, opacity: 1 };

export const defaultTurnMs = 260;

export const defaultSettings = (): Settings => ({
  bindings: cloneBindings(defaultBindings),
  handling: { ...defaultHandling },
  game: { ...defaultGameOptions },
  hud: { ...defaultHudOptions },
  turnMs: defaultTurnMs,
  screenShake: true,
});

/** The full engine configuration for the chosen options. */
export const configFor = (options: GameOptions): GameConfig => ({ ...defaultConfig, ...options });

const STORAGE_KEY = 'rotathree.settings.v1';

const numberIn = (value: unknown, min: number, max: number, fallback: number): number =>
  typeof value === 'number' && Number.isFinite(value) ? Math.min(max, Math.max(min, value)) : fallback;

/** Makes sense of whatever was stored; anything missing or out of range
 * falls back to its default. Settings saved by an older version of the game
 * lack the newer fields and simply get those at their defaults — the keys
 * the player chose are kept. */
export function sanitizeSettings(raw: unknown): Settings {
  const base = defaultSettings();
  if (typeof raw !== 'object' || raw === null) return base;
  const stored = raw as Record<string, unknown>;
  const handling = (stored.handling ?? {}) as Record<string, unknown>;
  const game = (stored.game ?? {}) as Record<string, unknown>;
  const hud = (stored.hud ?? {}) as Record<string, unknown>;
  return {
    bindings: sanitizeBindings(stored.bindings),
    handling: {
      dasMs: numberIn(handling.dasMs, 0, 400, base.handling.dasMs),
      arrMs: numberIn(handling.arrMs, 0, 150, base.handling.arrMs),
    },
    game: {
      activeStepSeconds: numberIn(game.activeStepSeconds, 0.1, 5, base.game.activeStepSeconds),
      inactiveStepSeconds: numberIn(game.inactiveStepSeconds, 0.2, 10, base.game.inactiveStepSeconds),
      armLength: Math.round(numberIn(game.armLength, 3, 12, base.game.armLength)),
      glassCount: Math.round(numberIn(game.glassCount, 2, 4, base.game.glassCount)),
      numberOfColors: Math.round(numberIn(game.numberOfColors, 3, MAX_COLORS, base.game.numberOfColors)),
      gravityScope: game.gravityScope === 'aboveCleared' ? 'aboveCleared' : 'wholeGlass',
      settleAfterBoardRotation: game.settleAfterBoardRotation === true,
    },
    hud: {
      keyHints: hud.keyHints !== false,
      score: hud.score !== false,
      stats: hud.stats !== false,
      opacity: numberIn(hud.opacity, 0.1, 1, base.hud.opacity),
    },
    turnMs: Math.round(numberIn(stored.turnMs, 0, 800, base.turnMs)),
    screenShake: stored.screenShake !== false,
  };
}

export function loadSettings(storage: Pick<Storage, 'getItem'> | null = safeStorage()): Settings {
  try {
    const text = storage?.getItem(STORAGE_KEY);
    return text ? sanitizeSettings(JSON.parse(text)) : defaultSettings();
  } catch {
    return defaultSettings();
  }
}

/** Returns whether the settings were actually written. */
export function saveSettings(
  settings: Settings,
  storage: Pick<Storage, 'setItem'> | null = safeStorage(),
): boolean {
  try {
    if (!storage) return false;
    storage.setItem(STORAGE_KEY, JSON.stringify(settings));
    return true;
  } catch {
    // Private mode or a full quota: the settings simply do not persist.
    return false;
  }
}

/** `localStorage`, or null where it is unavailable or forbidden. */
function safeStorage(): Storage | null {
  try {
    return globalThis.localStorage ?? null;
  } catch {
    return null;
  }
}
