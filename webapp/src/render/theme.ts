/** Tones of one block colour. */
export interface BlockTones {
  base: string;
  light: string;
  dark: string;
  /** `r, g, b` of the base colour, for building translucent variants. */
  rgb: string;
}

/** The names of the nine colour slots, in order. */
export const COLOUR_NAMES = [
  'Красный',
  'Синий',
  'Жёлтый',
  'Зелёный',
  'Фиолетовый',
  'Белый',
  'Оранжевый',
  'Голубой',
  'Розовый',
] as const;

/** The colours of the classic set, one per slot. */
export const DEFAULT_COLOURS: readonly string[] = [
  '#ff3d5e',
  '#3b82ff',
  '#ffc531',
  '#2fd985',
  '#a65cff',
  '#e4eafa',
  '#ff8a2e',
  '#2ee6f0',
  '#ff5fb0',
];

const channels = (hex: string): [number, number, number] => {
  const n = parseInt(hex.slice(1), 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
};

const toHex = (rgb: number[]): string =>
  `#${rgb.map((c) => Math.round(c).toString(16).padStart(2, '0')).join('')}`;

/** Lighter and darker tones of a colour, for the bevel of a block. */
export function toneOf(hex: string): BlockTones {
  const [r, g, b] = channels(hex);
  return {
    base: hex,
    light: toHex([r, g, b].map((c) => c + (255 - c) * 0.45)),
    dark: toHex([r, g, b].map((c) => c * (1 - 0.35))),
    rgb: `${r}, ${g}, ${b}`,
  };
}

/** How a block is drawn. The game is the same in every one — blocks of a
 * colour match — only their look changes. */
export type BlockSkin = 'classic' | 'retro' | 'colourDice';

/** The skins there are, in the order the settings offer them, with their
 * names. */
export const BLOCK_SKINS: readonly { id: BlockSkin; title: string }[] = [
  { id: 'classic', title: 'Классика' },
  { id: 'retro', title: 'Ретро' },
  { id: 'colourDice', title: 'Цветные кости' },
];

/** A stored skin, or the classic for anything else (or one no longer offered). */
export const blockSkin = (raw: unknown): BlockSkin =>
  BLOCK_SKINS.find((skin) => skin.id === raw)?.id ?? 'classic';

let tones: BlockTones[] = DEFAULT_COLOURS.map(toneOf);
let colours: readonly string[] = DEFAULT_COLOURS;
let skin: BlockSkin = 'classic';
let revision = 0;

/** Replaces the colours of the block slots. */
export function setPalette(next: readonly string[]): void {
  setLook(next, skin);
}

/** Replaces the colours of the block slots and how they are drawn. */
export function setLook(next: readonly string[], nextSkin: BlockSkin): void {
  if (next === colours && nextSkin === skin) return;
  colours = next;
  skin = nextSkin;
  tones = next.map(toneOf);
  revision++;
}

/** How the blocks are drawn now. */
export const currentSkin = (): BlockSkin => skin;

/** Changes every time the palette or the skin changes, so cached sprites can
 * be checked. */
export const paletteRevision = (): number => revision;

export const tonesOf = (color: number): BlockTones => tones[color];

/** The tones of every colour slot in the current palette. */
export const paletteTones = (): readonly BlockTones[] => tones;

export const THEME = {
  /** Accent of the active glass. */
  accent: '120, 205, 255',
  warning: '255, 176, 59',
  danger: '255, 70, 100',
  text: '236, 240, 255',
} as const;

export const rgba = (rgb: string, alpha: number): string => `rgba(${rgb}, ${alpha})`;
