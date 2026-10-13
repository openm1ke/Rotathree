import { describe, expect, it } from 'vitest';
import {
  DEFAULT_BUTTONS,
  DEFAULT_TWEAK,
  TWEAK_SCALE,
  TWEAK_SHIFT,
  buttonRects,
  sanitizeButtons,
  sanitizeShape,
  sanitizeTweak,
} from '../input/padShape';
import { defaultSettings, sanitizeSettings } from '../services/storage';

describe('the geometry of a pad', () => {
  it('without tweaks the buttons sit where the cross has always put them', () => {
    const rects = buttonRects({});
    const centre = (r: { x: number; y: number; size: number }) => [r.x + r.size / 2, r.y + r.size / 2];
    expect(centre(rects.center)[0]).toBeCloseTo(0.5, 9);
    expect(centre(rects.center)[1]).toBeCloseTo(0.5, 9);
    expect(centre(rects.up)[0]).toBeCloseTo(0.5, 9);
    expect(centre(rects.up)[1]).toBeCloseTo(1 / 6, 9);
    expect(centre(rects.left)[0]).toBeCloseTo(1 / 6, 9);
    expect(centre(rects.right)[0]).toBeCloseTo(5 / 6, 9);
    expect(centre(rects.down)[1]).toBeCloseTo(5 / 6, 9);
    // The Flutter app draws the arm 93 px wide on a 300 px pad.
    expect(rects.up.size).toBeCloseTo(93 / 300, 9);
  });

  it('a tweak scales a button about its own centre', () => {
    const rects = buttonRects({ center: { scale: 1.5, dx: 0, dy: 0 } });
    expect(rects.center.size).toBeCloseTo((80 / 300) * 1.5, 9);
    expect(rects.center.x + rects.center.size / 2).toBeCloseTo(0.5, 9);
    expect(rects.up.size).toBeCloseTo(93 / 300, 9);
  });

  it('a shift moves a button by a fraction of the pad', () => {
    const rects = buttonRects({ left: { scale: 1, dx: 0.1, dy: -0.05 } });
    expect(rects.left.x + rects.left.size / 2).toBeCloseTo(80 / 300, 9);
    expect(rects.left.y + rects.left.size / 2).toBeCloseTo(135 / 300, 9);
  });

  it('a button pushed off the pad is moved back on to it', () => {
    const rects = buttonRects({ up: { scale: 1.5, dx: 0, dy: -0.25 } });
    expect(rects.up.y).toBeGreaterThanOrEqual(0);
    expect(rects.up.y + rects.up.size).toBeLessThanOrEqual(1);
  });
});

describe('the settings of the buttons', () => {
  it('a tweak keeps its values in range, and bad values fall back', () => {
    expect(sanitizeTweak({ scale: 9, dx: -1, dy: 'high' })).toEqual({
      scale: TWEAK_SCALE.max,
      dx: -TWEAK_SHIFT,
      dy: 0,
    });
    expect(sanitizeTweak(null)).toEqual(DEFAULT_TWEAK);
  });

  it('an unknown shape falls back to the square cross', () => {
    expect(sanitizeShape('triangle')).toBe('triangle');
    expect(sanitizeShape('hexagon')).toBe('square');
    expect(sanitizeShape(undefined)).toBe('square');
  });

  it('the buttons are read back, and bad pads are left out', () => {
    const buttons = sanitizeButtons({ left: { up: { scale: 9, dx: -1 } }, right: 'x' });
    expect(buttons.left.up).toEqual({ scale: TWEAK_SCALE.max, dx: -TWEAK_SHIFT, dy: 0 });
    expect(buttons.right).toEqual({});
  });

  it('the settings keep the shape and the buttons', () => {
    const stored = JSON.parse(
      JSON.stringify({
        ...defaultSettings(),
        padShape: 'round',
        padButtons: { left: { center: { scale: 0.8, dx: 0.05, dy: 0 } }, right: {} },
      }),
    );
    const settings = sanitizeSettings(stored);
    expect(settings.padShape).toBe('round');
    expect(settings.padButtons.left.center).toEqual({ scale: 0.8, dx: 0.05, dy: 0 });
  });

  it('older saves get the square cross and no changed buttons', () => {
    const settings = sanitizeSettings({});
    expect(settings.padShape).toBe('square');
    expect(settings.padButtons).toEqual(DEFAULT_BUTTONS);
    expect(settings.hud.keyHints).toBe(true);
  });
});
