export type PadSide = 'left' | 'right';
export interface PadPlacement {
  size: number;
  x: number;
  y: number;
}
export type PadPositions = Record<PadSide, PadPlacement>;
export const DEFAULT_POSITIONS: PadPositions = {
  left: { size: 144, x: 0, y: 1 },
  right: { size: 144, x: 1, y: 1 },
};
export const PAD_MIN = 136,
  PAD_MAX = 216,
  PAD_GAP = 8;
const clamp = (n: number, max = 1, min = 0) => Math.max(min, Math.min(max, n));
export function sanitizePositions(raw: unknown): PadPositions {
  const value = (typeof raw === 'object' && raw !== null ? raw : {}) as Record<string, unknown>;
  const side = (key: PadSide) => {
    const p = (typeof value[key] === 'object' && value[key] !== null ? value[key] : {}) as Record<string, unknown>;
    const read = (name: keyof PadPlacement, min: number, max: number) =>
      typeof p[name] === 'number' && Number.isFinite(p[name])
        ? clamp(p[name] as number, max, min)
        : DEFAULT_POSITIONS[key][name];
    return { size: read('size', PAD_MIN, PAD_MAX), x: read('x', 0, 1), y: read('y', 0, 1) };
  };
  return { left: side('left'), right: side('right') };
}
export const padAreaHeight = (viewportHeight: number, positions: PadPositions, width: number) =>
  Math.max(
    Math.min(Math.max(positions.left.size, positions.right.size), (width - PAD_GAP) / 2),
    Math.min(260, viewportHeight * 0.32),
  );
export interface PadRect {
  size: number;
  x: number;
  y: number;
}
/** The same bounds are used by the game and editor. Pads cannot cover each other. */
export function padGeometry(width: number, height: number, positions: PadPositions): Record<PadSide, PadRect> {
  const rect = (p: PadPlacement): PadRect => {
    const size = Math.min(p.size, Math.max(PAD_MIN, (width - PAD_GAP) / 2), height);
    return { size, x: p.x * Math.max(0, width - size), y: p.y * Math.max(0, height - size) };
  };
  const left = rect(positions.left),
    right = rect(positions.right);
  const overlaps = (r: PadRect) =>
    r.x < left.x + left.size + PAD_GAP &&
    r.x + r.size + PAD_GAP > left.x &&
    r.y < left.y + left.size + PAD_GAP &&
    r.y + r.size + PAD_GAP > left.y;
  if (overlaps(right)) {
    const candidates = [
      { ...right, x: left.x + left.size + PAD_GAP },
      { ...right, x: left.x - right.size - PAD_GAP },
      { ...right, y: left.y + left.size + PAD_GAP },
      { ...right, y: left.y - right.size - PAD_GAP },
    ].filter((r) => r.x >= 0 && r.y >= 0 && r.x + r.size <= width && r.y + r.size <= height && !overlaps(r));
    candidates.sort((a, b) => Math.hypot(a.x - right.x, a.y - right.y) - Math.hypot(b.x - right.x, b.y - right.y));
    if (candidates[0]) Object.assign(right, candidates[0]);
    else {
      left.x = 0;
      right.x = Math.max(0, width - right.size);
    }
  }
  return { left, right };
}
export function movePad(
  positions: PadPositions,
  side: PadSide,
  x: number,
  y: number,
  width: number,
  height: number,
): PadPositions {
  const size = padGeometry(width, height, positions)[side].size;
  const next = {
    ...positions,
    [side]: { ...positions[side], x: clamp(x / Math.max(1, width - size)), y: clamp(y / Math.max(1, height - size)) },
  };
  const geometry = padGeometry(width, height, next);
  return Object.fromEntries(
    (['left', 'right'] as const).map((key) => [
      key,
      {
        ...next[key],
        x: width > geometry[key].size ? geometry[key].x / (width - geometry[key].size) : next[key].x,
        y: height > geometry[key].size ? geometry[key].y / (height - geometry[key].size) : next[key].y,
      },
    ]),
  ) as PadPositions;
}
