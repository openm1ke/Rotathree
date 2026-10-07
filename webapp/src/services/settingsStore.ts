import type { GameConfig, GravityScope } from '../game/config';
import { defaultConfig } from '../game/config';
import { cloneBindings, defaultBindings, sanitizeBindings, type Bindings } from '../input/bindings';
import { defaultHandling, type Handling } from '../input/keyboard';

/** The part of the game configuration the player can change. */
export interface GameOptions {
  activeStepSeconds: number;
  inactiveStepSeconds: number;
  armLength: number;
  numberOfColors: number;
  gravityScope: GravityScope;
  settleAfterBoardRotation: boolean;
}

export interface Settings {
  bindings: Bindings;
  handling: Handling;
  game: GameOptions;
  /** Board kicks and shakes on drops and pops. */
  screenShake: boolean;
}

export const defaultGameOptions: GameOptions = {
  activeStepSeconds: defaultConfig.activeStepSeconds,
  inactiveStepSeconds: defaultConfig.inactiveStepSeconds,
  armLength: defaultConfig.armLength,
  numberOfColors: defaultConfig.numberOfColors,
  gravityScope: defaultConfig.gravityScope,
  settleAfterBoardRotation: defaultConfig.settleAfterBoardRotation,
};

export const defaultSettings = (): Settings => ({
  bindings: cloneBindings(defaultBindings),
  handling: { ...defaultHandling },
  game: { ...defaultGameOptions },
  screenShake: true,
});

/** The full engine configuration for the chosen options. */
export const configFor = (options: GameOptions): GameConfig => ({ ...defaultConfig, ...options });

const STORAGE_KEY = 'rotathree.settings.v1';

const numberIn = (value: unknown, min: number, max: number, fallback: number): number =>
  typeof value === 'number' && Number.isFinite(value) ? Math.min(max, Math.max(min, value)) : fallback;

/** Makes sense of whatever was stored; anything missing or out of range
 * falls back to its default. */
export function sanitizeSettings(raw: unknown): Settings {
  const base = defaultSettings();
  if (typeof raw !== 'object' || raw === null) return base;
  const stored = raw as Record<string, unknown>;
  const handling = (stored.handling ?? {}) as Record<string, unknown>;
  const game = (stored.game ?? {}) as Record<string, unknown>;
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
      numberOfColors: Math.round(numberIn(game.numberOfColors, 3, 4, base.game.numberOfColors)),
      gravityScope: game.gravityScope === 'aboveCleared' ? 'aboveCleared' : 'wholeGlass',
      settleAfterBoardRotation: game.settleAfterBoardRotation === true,
    },
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

export function saveSettings(
  settings: Settings,
  storage: Pick<Storage, 'setItem'> | null = safeStorage(),
): void {
  try {
    storage?.setItem(STORAGE_KEY, JSON.stringify(settings));
  } catch {
    // Private mode or a full quota: the settings simply do not persist.
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
