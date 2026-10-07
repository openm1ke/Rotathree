/** How the game is played: a single run for survival, or Zen — the same
 * game through levels, each finished by reaching its score. */
export type GameMode = 'classic' | 'zen';

/** The numbers shown in the corners of the field. */
export interface HudState {
  score: number;
  combo: number;
  bestCombo: number;
  matches: number;
  pieces: number;
  seconds: number;
  /** Zen only (0 otherwise): the level being played, the points made in it
   * and the points it takes. */
  level: number;
  levelInto: number;
  levelTarget: number;
}

/** A short-lived callout: a score gain or a combo. */
export interface Callout {
  id: number;
  combo: number;
  score: number;
}

export const formatClock = (seconds: number): string =>
  `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`;

export const formatScore = (score: number): string => score.toLocaleString('ru-RU');
