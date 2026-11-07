// How a block is drawn, in a cell one unit wide centred on the origin: the
// same as the app's lib/ui/field/block_look.dart.
import type { BlockSkin, BlockTones } from './theme';

/** Half the side of a block in a cell one unit wide: blocks nearly touch, a
 * thin dark line between them, as close as Cube's. */
export const BLOCK_HALF = 0.485;

type Rgb = [number, number, number];

const rgbOf = (hex: string): Rgb => {
  const n = parseInt(hex.slice(1), 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
};

const mix = (a: Rgb, b: Rgb, t: number): Rgb => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];

const css = ([r, g, b]: Rgb, alpha = 1): string => `rgba(${Math.round(r)}, ${Math.round(g)}, ${Math.round(b)}, ${alpha})`;

const WHITE: Rgb = [255, 255, 255];
const BLACK: Rgb = [0, 0, 0];

/** How bright a colour looks, 0 to 1, as WCAG reckons it. */
export function luminance(hex: string): number {
  const linear = (c: number): number => {
    const v = c / 255;
    return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
  };
  const [r, g, b] = rgbOf(hex);
  return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b);
}

/** The colour of a pip on a block of `tones`: white, or dark on a block too
 * light for white to show. */
export const markColour = (tones: BlockTones): string =>
  luminance(tones.base) > 0.72 ? '#2a2633' : 'rgba(255, 255, 255, 0.97)';

/** Where the pips of one to nine are, as on dice, then as a three-by-three. */
const PIPS: readonly (readonly [number, number])[][] = [
  [[0, 0]],
  [[-1, -1], [1, 1]],
  [[-1, -1], [0, 0], [1, 1]],
  [[-1, -1], [1, -1], [-1, 1], [1, 1]],
  [[-1, -1], [1, -1], [0, 0], [-1, 1], [1, 1]],
  [[-1, -1], [1, -1], [-1, 0], [1, 0], [-1, 1], [1, 1]],
  [[-1, -1], [1, -1], [-1, 0], [0, 0], [1, 0], [-1, 1], [1, 1]],
  [[-1, -1], [0, -1], [1, -1], [-1, 0], [1, 0], [-1, 1], [0, 1], [1, 1]],
  [[-1, -1], [0, -1], [1, -1], [-1, 0], [0, 0], [1, 0], [-1, 1], [0, 1], [1, 1]],
];

/** The pips on a block of colour `slot` in `skin`, as centres and a radius
 * in face coordinates (-0.5 to 0.5, y down): as many as the slot's number on
 * dice, none on the others. */
export function pipsOf(skin: BlockSkin, slot: number): { x: number; y: number; r: number }[] {
  if (skin !== 'colourDice') return [];
  const layout = PIPS[slot % PIPS.length];
  const r = layout.length > 6 ? 0.062 : layout.length === 1 ? 0.1 : 0.072;
  return layout.map(([x, y]) => ({ x: x * 0.2, y: y * 0.2, r }));
}

function roundedRect(g: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number): void {
  const radius = Math.max(0, Math.min(r, w / 2, h / 2));
  g.beginPath();
  g.moveTo(x + radius, y);
  g.arcTo(x + w, y, x + w, y + h, radius);
  g.arcTo(x + w, y + h, x, y + h, radius);
  g.arcTo(x, y + h, x, y, radius);
  g.arcTo(x, y, x + w, y, radius);
  g.closePath();
}

/** A square of half-side `half` with corners of `radius`, centred. */
const square = (g: CanvasRenderingContext2D, half: number, radius: number, dy = 0): void =>
  roundedRect(g, -half, -half + dy, half * 2, half * 2, radius);

/** The block of colour `slot` in `skin`, in a cell one unit wide centred on
 * the origin of `g`: a cushion (classic, and rounder for dice) or a retro
 * square, and the skin's pips on it. Nothing leaves the cell. */
export function paintBlock(g: CanvasRenderingContext2D, tones: BlockTones, skin: BlockSkin, slot: number): void {
  g.save();
  g.beginPath();
  g.rect(-0.5, -0.5, 1, 1);
  g.clip();
  if (skin === 'retro') paintRetro(g, tones);
  else paintCushion(g, tones, skin === 'colourDice' ? 0.21 : 0.17, skin === 'colourDice' ? 0.7 : 1);
  const ink = markColour(tones);
  for (const pip of pipsOf(skin, slot)) {
    g.beginPath();
    g.arc(pip.x, pip.y + 0.016, pip.r, 0, Math.PI * 2);
    g.fillStyle = 'rgba(0, 0, 0, 0.35)';
    g.fill();
    g.beginPath();
    g.arc(pip.x, pip.y, pip.r, 0, Math.PI * 2);
    g.fillStyle = ink;
    g.fill();
  }
  g.restore();
}

/** A cushion of the block's colour: one piece with no seam, its edges round
 * — the light running down them at the top left, the shade at the bottom
 * right — its middle domed towards the light, a soft gloss and a glint. */
function paintCushion(g: CanvasRenderingContext2D, tones: BlockTones, radius: number, gloss: number): void {
  const h = BLOCK_HALF;
  const base = rgbOf(tones.base);
  const light = rgbOf(tones.light);
  const dark = rgbOf(tones.dark);

  // The shadow it casts on what is under it.
  square(g, h, radius, 0.015);
  g.fillStyle = 'rgba(0, 0, 0, 0.36)';
  g.fill();

  // The block's slope, lit at the top left.
  const slope = g.createLinearGradient(-h, -h, h, h);
  slope.addColorStop(0, css(mix(base, light, 0.45)));
  slope.addColorStop(0.5, css(base));
  slope.addColorStop(1, css(mix(base, dark, 0.5)));
  square(g, h, radius);
  g.fillStyle = slope;
  g.fill();

  g.save();
  square(g, h, radius);
  g.clip();
  // The round edge: rings from the rim inwards, each fainter, lit towards
  // the top left and shaded towards the bottom right.
  const rings = 8;
  g.lineWidth = 0.016;
  for (let i = 0; i < rings; i++) {
    const inset = 0.007 + i * 0.015;
    const strength = (1 - i / rings) ** 1.6;
    const lit = g.createLinearGradient(-h, -h, 0.1, 0.1);
    lit.addColorStop(0, css(WHITE, 0.42 * strength));
    lit.addColorStop(1, css(WHITE, 0));
    square(g, h - inset, radius - inset);
    g.strokeStyle = lit;
    g.stroke();
    const shaded = g.createLinearGradient(h, h, -0.1, -0.1);
    shaded.addColorStop(0, css(BLACK, 0.42 * strength));
    shaded.addColorStop(1, css(BLACK, 0));
    g.strokeStyle = shaded;
    g.stroke();
  }

  // The middle, domed towards the light.
  const dome = g.createRadialGradient(-0.1, -0.14, 0, -0.1, -0.14, 0.5);
  dome.addColorStop(0, css(mix(base, light, 0.35), 0.75));
  dome.addColorStop(1, css(base, 0));
  square(g, h, radius);
  g.fillStyle = dome;
  g.fill();

  // A soft gloss across the top, and a glint in its corner.
  g.save();
  g.translate(-0.03, -0.2);
  g.scale(1, 0.42);
  const shine = g.createRadialGradient(0, 0, 0, 0, 0, 0.34);
  shine.addColorStop(0, css(WHITE, 0.5 * gloss));
  shine.addColorStop(0.6, css(WHITE, 0.12 * gloss));
  shine.addColorStop(1, css(WHITE, 0));
  g.beginPath();
  g.arc(0, 0, 0.34, 0, Math.PI * 2);
  g.fillStyle = shine;
  g.fill();
  g.restore();
  const glint = g.createRadialGradient(-0.22, -0.22, 0, -0.22, -0.22, 0.075);
  glint.addColorStop(0, css(WHITE, 0.85 * gloss));
  glint.addColorStop(1, css(WHITE, 0));
  g.beginPath();
  g.arc(-0.22, -0.22, 0.075, 0, Math.PI * 2);
  g.fillStyle = glint;
  g.fill();
  g.restore();

  // A dark rim round it all keeps neighbours apart.
  square(g, h - 0.006, radius - 0.006);
  g.lineWidth = 0.012;
  g.strokeStyle = css(mix(dark, BLACK, 0.35), 0.6);
  g.stroke();
}

/** The old games' block: square, four hard bevels of four tones round a flat
 * face, and a glint of white in its corner. */
function paintRetro(g: CanvasRenderingContext2D, tones: BlockTones): void {
  const base = rgbOf(tones.base);
  const light = rgbOf(tones.light);
  const dark = rgbOf(tones.dark);
  const facet = (points: number[][], colour: string): void => {
    g.beginPath();
    g.moveTo(points[0][0], points[0][1]);
    for (const [x, y] of points.slice(1)) g.lineTo(x, y);
    g.closePath();
    g.fillStyle = colour;
    g.fill();
  };
  const o = 0.49;
  g.fillStyle = css(mix(dark, BLACK, 0.45));
  g.fillRect(-o, -o, o * 2, o * 2);
  const b = o - 0.02;
  const f = b - 0.11;
  facet([[-b, -b], [b, -b], [f, -f], [-f, -f]], css(mix(light, WHITE, 0.3)));
  facet([[-b, -b], [-f, -f], [-f, f], [-b, b]], css(mix(base, light, 0.45)));
  facet([[b, -b], [b, b], [f, f], [f, -f]], css(mix(base, dark, 0.5)));
  facet([[-b, b], [-f, f], [f, f], [b, b]], css(dark));
  g.fillStyle = css(base);
  g.fillRect(-f, -f, f * 2, f * 2);
  // The glint: a square and a short stroke, as the pixels of old.
  const inner = o - 0.13;
  g.fillStyle = 'rgba(255, 255, 255, 0.9)';
  g.fillRect(-inner + 0.02, -inner + 0.02, 0.075, 0.075);
  g.fillStyle = 'rgba(255, 255, 255, 0.55)';
  g.fillRect(-inner + 0.095, -inner + 0.02, 0.12, 0.035);
}

/** A row of blocks of `colours` in `skin` on a canvas `unit` CSS pixels a
 * block, at the screen's pixel density: for the settings and the banners. */
export function drawBlockRow(
  canvas: HTMLCanvasElement,
  skin: BlockSkin,
  tones: readonly BlockTones[],
  unit: number,
): void {
  const ratio = Math.min(3, window.devicePixelRatio || 1);
  canvas.width = Math.round(unit * tones.length * ratio);
  canvas.height = Math.round(unit * ratio);
  // As wide as asked, narrower when the room is (max-width), always in
  // proportion.
  canvas.style.width = `${unit * tones.length}px`;
  canvas.style.maxWidth = '100%';
  canvas.style.height = 'auto';
  canvas.style.aspectRatio = `${tones.length} / 1`;
  const g = canvas.getContext('2d');
  if (!g) return;
  g.clearRect(0, 0, canvas.width, canvas.height);
  tones.forEach((tone, slot) => {
    g.setTransform(unit * ratio, 0, 0, unit * ratio, (slot + 0.5) * unit * ratio, (unit * ratio) / 2);
    paintBlock(g, tone, skin, slot);
  });
  g.setTransform(1, 0, 0, 1, 0, 0);
}
