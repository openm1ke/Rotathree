import type { PadSide } from './padPlacement';
import { PAD_SLOTS, type PadSlot } from './pads';

/** The outline of every pad button. Square is the look the buttons have always had. */
export type PadShape = 'square' | 'round' | 'triangle';
export const PAD_SHAPES: readonly PadShape[] = ['square', 'round', 'triangle'];
export const SHAPE_LABELS: Record<PadShape, string> = {
  square: 'Квадратные',
  round: 'Круглые',
  triangle: 'Треугольные',
};

/** One button's size and place, relative to where its cross puts it: the size
 * as a factor of the default size, and the shift as fractions of the pad. */
export interface PadTweak {
  scale: number;
  dx: number;
  dy: number;
}
export const DEFAULT_TWEAK: PadTweak = { scale: 1, dx: 0, dy: 0 };
export const TWEAK_SCALE = { min: 0.5, max: 1.5 };
export const TWEAK_SHIFT = 0.25;

/** The tweaks of one pad, by button. A button without an entry is untouched. */
export type PadTweaks = Partial<Record<PadSlot, PadTweak>>;
export type PadButtons = Record<PadSide, PadTweaks>;
export const DEFAULT_BUTTONS: PadButtons = { left: {}, right: {} };

/** The cross is a 3 by 3 grid: up, left, centre, right and down. */
const CELL: Record<PadSlot, readonly [number, number]> = {
  up: [1, 0],
  left: [0, 1],
  center: [1, 1],
  right: [2, 1],
  down: [1, 2],
};

/** A square as fractions of the pad: its left, top and side. */
export interface Fraction {
  x: number;
  y: number;
  size: number;
}

const inside = (start: number, length: number): number => {
  if (start < 0) return -start;
  if (start + length > 1) return 1 - (start + length);
  return 0;
};

/**
 * Where every button of a pad sits, as fractions of the pad. Without tweaks
 * this is the cross the game has always drawn. A tweak scales a button about
 * its own centre and shifts it, and a button that would leave the pad is moved
 * back on to it. The Flutter app uses the same arithmetic.
 */
export function buttonRects(tweaks: PadTweaks): Record<PadSlot, Fraction> {
  const cell = 1 / 3;
  const rects = {} as Record<PadSlot, Fraction>;
  for (const slot of PAD_SLOTS) {
    const [column, row] = CELL[slot];
    // The arms keep a thin gap between them; the centre keeps a wider one.
    const inset = cell * (slot === 'center' ? 0.1 : 0.035);
    const base = { x: column * cell + inset, y: row * cell + inset, size: cell - 2 * inset };
    const tweak = { ...DEFAULT_TWEAK, ...tweaks[slot] };
    const size = base.size * tweak.scale;
    let x = base.x + base.size / 2 + tweak.dx - size / 2;
    let y = base.y + base.size / 2 + tweak.dy - size / 2;
    x += inside(x, size);
    y += inside(y, size);
    rects[slot] = { x, y, size };
  }
  return rects;
}

/** The corners of a triangular button in its own 100 by 100 box, pointing away
 * from the centre of the pad. */
export const TRIANGLE_POINTS: Record<PadSlot, string> = {
  up: '50,0 100,100 0,100',
  center: '50,0 100,100 0,100',
  down: '0,0 100,0 50,100',
  left: '0,50 100,0 100,100',
  right: '100,50 0,100 0,0',
};

const clamp = (n: number, min: number, max: number) => Math.min(max, Math.max(min, n));

/** Reads a stored tweak; anything missing or out of range falls back. */
export function sanitizeTweak(raw: unknown): PadTweak {
  const value = (typeof raw === 'object' && raw !== null ? raw : {}) as Record<string, unknown>;
  const read = (key: keyof PadTweak, min: number, max: number, fallback: number) =>
    typeof value[key] === 'number' && Number.isFinite(value[key] as number)
      ? clamp(value[key] as number, min, max)
      : fallback;
  return {
    scale: read('scale', TWEAK_SCALE.min, TWEAK_SCALE.max, 1),
    dx: read('dx', -TWEAK_SHIFT, TWEAK_SHIFT, 0),
    dy: read('dy', -TWEAK_SHIFT, TWEAK_SHIFT, 0),
  };
}

export function sanitizeButtons(raw: unknown): PadButtons {
  const value = (typeof raw === 'object' && raw !== null ? raw : {}) as Record<string, unknown>;
  const side = (key: PadSide): PadTweaks => {
    const pad = (typeof value[key] === 'object' && value[key] !== null ? value[key] : {}) as Record<string, unknown>;
    return Object.fromEntries(
      PAD_SLOTS.filter((slot) => pad[slot] !== undefined).map((slot) => [slot, sanitizeTweak(pad[slot])]),
    ) as PadTweaks;
  };
  return { left: side('left'), right: side('right') };
}

export function sanitizeShape(raw: unknown): PadShape {
  return PAD_SHAPES.includes(raw as PadShape) ? (raw as PadShape) : 'square';
}
