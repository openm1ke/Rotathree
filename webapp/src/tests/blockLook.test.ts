import { describe, expect, it } from 'vitest';
import { luminance, markColour, pipsOf } from '../render/blockLook';
import { BLOCK_SKINS, blockSkin, toneOf } from '../render/theme';

describe('block skins', () => {
  it('three skins, and one no longer offered is read as the classic', () => {
    expect(BLOCK_SKINS.map((skin) => skin.id)).toEqual(['classic', 'retro', 'colourDice']);
    expect(blockSkin('retro')).toBe('retro');
    for (const gone of ['dice', 'neon', 'gems', 'symbols', 42, null]) expect(blockSkin(gone)).toBe('classic');
  });

  it('a die shows its colour\'s number in pips, inside its face', () => {
    for (let slot = 0; slot < 9; slot++) {
      const pips = pipsOf('colourDice', slot);
      expect(pips).toHaveLength(slot + 1);
      for (const { x, y, r } of pips) {
        expect(Math.abs(x) + r).toBeLessThan(0.36);
        expect(Math.abs(y) + r).toBeLessThan(0.36);
      }
      expect(pipsOf('classic', slot)).toHaveLength(0);
      expect(pipsOf('retro', slot)).toHaveLength(0);
    }
  });

  it('pips are white, and dark on a block too light for white', () => {
    expect(luminance('#ffffff')).toBeCloseTo(1);
    expect(luminance('#000000')).toBe(0);
    expect(markColour(toneOf('#3b82ff'))).toBe('rgba(255, 255, 255, 0.97)');
    expect(markColour(toneOf('#e4eafa'))).toBe('#2a2633');
  });
});
