/** The numbers shown in the corners of the field. */
export interface HudState {
  /** Points of the whole game so far. */
  score: number;
  combo: number;
  bestCombo: number;
  matches: number;
  pieces: number;
  seconds: number;
  /** Campaign only (0 otherwise): the level being played, from 1, the points
   * made in it, the points it takes, and its colours and glasses. */
  level: number;
  into: number;
  target: number;
  colours: number;
  glasses: number;
  /** Modes whose falling speeds up: the speed level, from 1 (0 otherwise). */
  speed: number;
}

export const EMPTY_HUD: HudState = {
  score: 0,
  combo: 0,
  bestCombo: 0,
  matches: 0,
  pieces: 0,
  seconds: 0,
  level: 0,
  into: 0,
  target: 0,
  colours: 0,
  glasses: 0,
  speed: 0,
};

/** A short-lived callout: a score gain with its combo, or a new speed. */
export interface Callout {
  id: number;
  kind: 'score' | 'speed';
  score?: number;
  combo?: number;
  speed?: number;
}

export const sameHud = (a: HudState, b: HudState): boolean =>
  (Object.keys(a) as (keyof HudState)[]).every((key) => a[key] === b[key]);

export const formatClock = (seconds: number): string =>
  `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`;

export const formatScore = (score: number): string => score.toLocaleString('ru-RU');
