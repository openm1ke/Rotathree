import { describe, expect, it } from 'vitest';
import { DEFAULT_COLOURS, paletteRevision, paletteTones, setPalette, toneOf } from '../render/theme';

describe('block colours', () => {
  it('a colour gets a lighter and a darker tone for its bevel', () => {
    const tones = toneOf('#000000');
    expect(tones.base).toBe('#000000');
    expect(tones.light).toBe('#737373');
    expect(tones.dark).toBe('#000000');
    expect(tones.rgb).toBe('0, 0, 0');
  });

  it('nine slots, and a new palette replaces them all', () => {
    expect(DEFAULT_COLOURS).toHaveLength(9);
    const before = paletteRevision();
    setPalette(['#ff0000', '#00ff00', '#0000ff']);
    expect(paletteRevision()).toBe(before + 1);
    expect(paletteTones()).toHaveLength(3);
    expect(paletteTones()[1].base).toBe('#00ff00');
    setPalette(DEFAULT_COLOURS);
    expect(paletteTones()).toHaveLength(9);
  });
});
