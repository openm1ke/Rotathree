// Cube's campaign: eight levels, each a game of its own with a score to
// reach. They bring in one thing at a time: more colours, a bigger cube,
// the glasses in front and behind dropping their sticks by themselves,
// quicker falling.
import type { Progress } from '../services/storage';
import type { CubeConfig } from './rules';

export interface CubeLevel {
  /** A word or two for the level's tile. */
  title: string;
  colours: number;
  /** Side of the cube in the middle, and width of every glass. */
  width: number;
  arm: number;
  /** The glasses in front and behind drop their sticks by themselves. */
  depthFalls: boolean;
  target: number;
  activeStep: number;
  inactiveStep: number;
}

/** The targets were set from a greedy bot that never tips the cube (lost
 * within two or three minutes, as the glasses it leaves alone fill up): it
 * reaches each of them on most seeds, a player who tips and turns the cube
 * well before. */
export const CUBE_CAMPAIGN: readonly CubeLevel[] = [
  { title: 'Первые линии', colours: 3, width: 7, arm: 8, depthFalls: false, target: 1500, activeStep: 1, inactiveStep: 3 },
  { title: 'Четыре цвета', colours: 4, width: 7, arm: 8, depthFalls: false, target: 2000, activeStep: 1, inactiveStep: 3 },
  { title: 'Куб побольше', colours: 4, width: 9, arm: 9, depthFalls: false, target: 2500, activeStep: 1, inactiveStep: 3 },
  { title: 'Глубина оживает', colours: 4, width: 9, arm: 9, depthFalls: true, target: 3000, activeStep: 1, inactiveStep: 3 },
  { title: 'Пять цветов', colours: 5, width: 9, arm: 9, depthFalls: true, target: 3000, activeStep: 1, inactiveStep: 3 },
  { title: 'Быстрее', colours: 5, width: 10, arm: 9, depthFalls: true, target: 3200, activeStep: 0.9, inactiveStep: 2.8 },
  { title: 'Шесть цветов', colours: 6, width: 10, arm: 10, depthFalls: true, target: 3400, activeStep: 0.9, inactiveStep: 2.8 },
  { title: 'Финал', colours: 6, width: 10, arm: 10, depthFalls: true, target: 3800, activeStep: 0.85, inactiveStep: 2.6 },
];

export const CUBE_CAMPAIGN_LAST = CUBE_CAMPAIGN.length - 1;

/** The rules of a level: no speed-up, the steps are the level's own. */
export const cubeLevelConfig = (level: CubeLevel): Partial<CubeConfig> => ({
  centre: level.width,
  arm: level.arm,
  numberOfColors: level.colours,
  depthFalls: level.depthFalls,
  activeStepSeconds: level.activeStep,
  inactiveStepSeconds: level.inactiveStep,
  ramp: null,
});

export const defaultCubeProgress = (): Progress => ({
  unlocked: 0,
  completed: false,
  best: CUBE_CAMPAIGN.map(() => 0),
});

/** Makes sense of a stored Cube campaign progress. */
export function sanitizeCubeProgress(raw: unknown): Progress {
  const base = defaultCubeProgress();
  if (typeof raw !== 'object' || raw === null) return base;
  const stored = raw as Record<string, unknown>;
  const whole = (value: unknown, max: number) =>
    typeof value === 'number' && Number.isFinite(value) ? Math.round(Math.min(max, Math.max(0, value))) : 0;
  return {
    unlocked: whole(stored.unlocked, CUBE_CAMPAIGN_LAST),
    completed: stored.completed === true,
    best: base.best.map((_, i) => whole(Array.isArray(stored.best) ? stored.best[i] : 0, 1e9)),
  };
}

/** The progress once `index` has been passed with `score`. */
export function passCubeLevel(progress: Progress, index: number, score: number): Progress {
  return {
    unlocked: Math.max(progress.unlocked, Math.min(index + 1, CUBE_CAMPAIGN_LAST)),
    completed: progress.completed || index === CUBE_CAMPAIGN_LAST,
    best: progress.best.map((value, i) => (i === index ? Math.max(value, score) : value)),
  };
}
