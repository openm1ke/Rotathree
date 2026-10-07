import type { BlockColor } from '../game/piece';

/** Tones of one block colour. */
export interface BlockTones {
  base: string;
  light: string;
  dark: string;
  /** `r, g, b` of the base colour, for building translucent variants. */
  rgb: string;
}

export const BLOCK_TONES: readonly BlockTones[] = [
  { base: '#ff3d5e', light: '#ff96a8', dark: '#a8132f', rgb: '255, 61, 94' },
  { base: '#3b82ff', light: '#93bbff', dark: '#1646b8', rgb: '59, 130, 255' },
  { base: '#ffc531', light: '#ffe696', dark: '#b97c00', rgb: '255, 197, 49' },
  { base: '#2fd985', light: '#93f2c2', dark: '#0d8a4d', rgb: '47, 217, 133' },
  { base: '#a65cff', light: '#d6b3ff', dark: '#5a1fbd', rgb: '166, 92, 255' },
  { base: '#e4eafa', light: '#ffffff', dark: '#8a94b4', rgb: '228, 234, 250' },
];

export const tonesOf = (color: BlockColor): BlockTones => BLOCK_TONES[color];

export const THEME = {
  /** Accent of the active glass. */
  accent: '120, 205, 255',
  warning: '255, 176, 59',
  danger: '255, 70, 100',
  text: '236, 240, 255',
} as const;

export const rgba = (rgb: string, alpha: number): string => `rgba(${rgb}, ${alpha})`;
