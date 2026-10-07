/** The numbers shown in the corners of the field. */
export interface HudState {
  score: number;
  combo: number;
  bestCombo: number;
  matches: number;
  pieces: number;
  seconds: number;
}

/** A short-lived callout: a score gain or a combo. */
export interface Callout {
  id: number;
  combo: number;
  score: number;
}

export const formatClock = (seconds: number): string =>
  `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`;
