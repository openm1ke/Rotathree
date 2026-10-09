import type { Side } from '../game/side';

export interface FieldViewport {
  left: number; top: number; right: number; bottom: number;
  cx: number; cy: number; span: number; grow: number;
}
const ease = (t: number): number => 1 - (1 - Math.max(0, Math.min(1, t))) ** 3;

/** Fit only the arms in play. Reframe first, then build the new arm into the space. */
export function fieldViewport(n: number, arm: number, sides: readonly Side[], angle = 0,
  building: Side | null = null, progress = 1, reduceMotion = false): FieldViewport {
  const half = n / 2;
  const bounds = (visible: readonly Side[]) => {
    let left = Infinity, top = Infinity, right = -Infinity, bottom = -Infinity;
    const rect = (x1: number, y1: number, x2: number, y2: number, turn: number) => {
      const c = Math.cos(turn), s = Math.sin(turn);
      for (const x of [x1, x2]) for (const y of [y1, y2]) {
        const px = c * x - s * y, py = s * x + c * y;
        left = Math.min(left, px); right = Math.max(right, px);
        top = Math.min(top, py); bottom = Math.max(bottom, py);
      }
    };
    rect(-half, -half, half, half, angle);
    for (const side of visible) rect(-half, -half - arm, half, -half, angle + side * Math.PI / 2);
    // A little more breathing room with each added glass makes every addition readable.
    const pad = Math.max(0, visible.length - 1) * 0.25;
    return { left: left - pad, top: top - pad, right: right + pad, bottom: bottom + pad };
  };
  const after = bounds(sides);
  const before = building === null ? after : bounds(sides.filter((side) => side !== building));
  const t = building === null || reduceMotion ? 1 : ease(progress / 0.4);
  const lerp = (a: number, b: number) => a + (b - a) * t;
  const left = lerp(before.left, after.left), top = lerp(before.top, after.top);
  const right = lerp(before.right, after.right), bottom = lerp(before.bottom, after.bottom);
  return { left, top, right, bottom, cx: (left + right) / 2, cy: (top + bottom) / 2,
    span: Math.max(right - left, bottom - top),
    grow: building === null || reduceMotion ? 1 : ease((progress - 0.25) / 0.75) };
}
