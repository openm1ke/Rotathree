import { defaultConfig, type GameConfig, type GravityScope } from './config';
import type { SpeedRamp } from './engine';

/** The modes a game can be played in. */
export type ModeId = 'campaign' | 'insane' | 'custom';

export const MODE_NAMES: Record<ModeId, string> = {
  campaign: 'Кампания',
  insane: 'Кошмар',
  custom: 'Кастом',
};

/** What the custom mode is set up with; kept between launches. */
export interface CustomSetup {
  /** Glasses besides the one the game starts in: 0 to 3. */
  extraGlasses: number;
  /** Colours in the pieces: 3 to 9. */
  colours: number;
  armLength: number;
  activeStep: number;
  inactiveStep: number;
  /** Whether the falling speeds up with the score. */
  speedUp: boolean;
  /** How much faster each speed-up makes it, as a fraction (0.1 = 10%). */
  speedUpStep: number;
  /** Points between two speed-ups. */
  speedUpEvery: number;
  gravityScope: GravityScope;
}

export const DEFAULT_CUSTOM: CustomSetup = {
  extraGlasses: 3,
  colours: 3,
  armLength: 9,
  activeStep: 1,
  inactiveStep: 3,
  speedUp: false,
  speedUpStep: 0.1,
  speedUpEvery: 1000,
  gravityScope: 'wholeGlass',
};

export const CUSTOM_LIMITS = {
  extraGlasses: [0, 3],
  colours: [3, 9],
  armLength: [4, 12],
  activeStep: [0.3, 2],
  inactiveStep: [0.6, 6],
  speedUpStep: [0.02, 0.3],
  speedUpEvery: [200, 5000],
} as const;

const clamp = (value: number, [min, max]: readonly [number, number]): number =>
  Math.min(max, Math.max(min, Number.isFinite(value) ? value : min));

/** Makes sense of stored or edited custom values. */
export function sanitizeCustom(raw: unknown): CustomSetup {
  const r = (typeof raw === 'object' && raw !== null ? raw : {}) as Record<string, unknown>;
  const num = (key: keyof typeof CUSTOM_LIMITS, fallback: number): number =>
    typeof r[key] === 'number' ? clamp(r[key] as number, CUSTOM_LIMITS[key]) : fallback;
  return {
    extraGlasses: Math.round(num('extraGlasses', DEFAULT_CUSTOM.extraGlasses)),
    colours: Math.round(num('colours', DEFAULT_CUSTOM.colours)),
    armLength: Math.round(num('armLength', DEFAULT_CUSTOM.armLength)),
    activeStep: num('activeStep', DEFAULT_CUSTOM.activeStep),
    inactiveStep: num('inactiveStep', DEFAULT_CUSTOM.inactiveStep),
    speedUp: r.speedUp === true,
    speedUpStep: num('speedUpStep', DEFAULT_CUSTOM.speedUpStep),
    speedUpEvery: Math.round(num('speedUpEvery', DEFAULT_CUSTOM.speedUpEvery)),
    gravityScope: r.gravityScope === 'aboveCleared' ? 'aboveCleared' : 'wholeGlass',
  };
}

/** A run: the engine configuration and, for modes that speed up, the ramp. */
export interface RunPlan {
  config: GameConfig;
  ramp: SpeedRamp | null;
}

/** Insane: six colours, four glasses, and the falling speeds up with every
 * thousand points until a glass overflows. It starts at the speed of the
 * last campaign level. */
export const insanePlan = (): RunPlan => ({
  config: {
    ...defaultConfig,
    glassCount: 4,
    numberOfColors: 6,
    activeStepSeconds: 0.9,
    inactiveStepSeconds: 2.6,
  },
  ramp: { everyPoints: 1000, factor: 0.93, minActive: 0.15, minInactive: 0.5 },
});

/** Custom: everything from the setup; the speed-up is optional. */
export const customPlan = (setup: CustomSetup): RunPlan => ({
  config: {
    ...defaultConfig,
    glassCount: 1 + setup.extraGlasses,
    numberOfColors: setup.colours,
    armLength: setup.armLength,
    activeStepSeconds: setup.activeStep,
    inactiveStepSeconds: setup.inactiveStep,
    gravityScope: setup.gravityScope,
  },
  ramp: setup.speedUp
    ? { everyPoints: setup.speedUpEvery, factor: 1 - setup.speedUpStep, minActive: 0.2, minInactive: 0.6 }
    : null,
});
