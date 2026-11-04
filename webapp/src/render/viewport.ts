import type { Side } from '../game/side';

export interface FieldViewport {
  left: number; top: number; right: number; bottom: number;
  cx: number; cy: number; span: number; grow: number;
}
const ease = (t: number): number => 1 - (1 - Math.max(0, Math.min(1, t))) ** 3;

/** Centered above a glass's entry with an air gap, in that glass's cell axes. */
export const nextPiecePreviewRect = (n: number, arm: number) => ({
  x: -Math.min(3.6, n) / 2, y: -n / 2 - arm - 2.2, width: Math.min(3.6, n), height: 1.6,
});

/** Fit the arms around the fixed board center; make room before growing a new arm. */
export function fieldViewport(n: number, arm: number, sides: readonly Side[], angle = 0,
  building: Side | null = null, progress = 1, reduceMotion = false, focusSingleGlass = false, showNextPiece = false): FieldViewport {
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
    for (const side of visible) {
      const turn = angle + side * Math.PI / 2;
      rect(-half, -half - arm, half, -half, turn);
      if (showNextPiece) {
        const p = nextPiecePreviewRect(n, arm);
        rect(p.x, p.y, p.x + p.width, p.y + p.height, turn);
      }
    }
    if (focusSingleGlass && visible.length === 1) return { left, top, right, bottom };
    // A little more breathing room with each added glass makes every addition readable.
    const pad = Math.max(0, visible.length - 1) * 0.25;
    const rx = Math.max(Math.abs(left), Math.abs(right)) + pad;
    const ry = Math.max(Math.abs(top), Math.abs(bottom)) + pad;
    return { left: -rx, top: -ry, right: rx, bottom: ry };
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

/** Steps a quarter turn is sampled in: every quarter turn looks the same to
 * the camera. */
const TURN_STEPS = 64;

/** Spans of the field, in cells, that its textures are drawn for. */
export interface TextureSpans {
  /** The cross at rest: blocks are copied to the screen pixel for pixel. */
  rest: number;
  /** Glows: the cross at rest or, while a glass grows in, the closer view
   * without it that the camera starts from. */
  glow: number;
  /** The closest the camera comes while it turns or a glass grows in, so
   * that moving blocks are only ever scaled down. */
  motion: number;
}

export function textureSpans(n: number, arm: number, sides: readonly Side[], growing: Side | null = null,
  focusSingleGlass = false, showNextPiece = false): TextureSpans {
  const span = (visible: readonly Side[], angle: number) =>
    fieldViewport(n, arm, visible, angle, null, 1, false, focusSingleGlass, showNextPiece).span;
  const layouts = growing === null ? [sides] : [sides, sides.filter((side) => side !== growing)];
  const rest = span(sides, 0);
  const glow = Math.min(...layouts.map((visible) => span(visible, 0)));
  let motion = glow;
  for (const visible of layouts) for (let step = 1; step < TURN_STEPS; step++) {
    motion = Math.min(motion, span(visible, step * Math.PI / 2 / TURN_STEPS));
  }
  return { rest, glow, motion };
}
