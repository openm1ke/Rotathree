import { describe, expect, it } from 'vitest';
import { GLASS_ORDER } from '../game/config';
import { fieldViewport } from '../render/viewport';

describe('field camera', () => {
  it('reserves space around the board center and steps back with each addition', () => {
    const views = [1, 2, 3, 4].map((count) => fieldViewport(6, 9, GLASS_ORDER.slice(0, count)));
    expect(views[0].span).toBe(24);
    for (let i = 1; i < views.length; i++) expect(views[i].span).toBeGreaterThan(views[i - 1].span);
  });

  it('keeps the board centered throughout rotations and building with any glass count', () => {
    for (let count = 1; count <= 4; count++) {
      const sides = GLASS_ORDER.slice(0, count);
      for (let step = 0; step <= 32; step++) for (const progress of [0, 0.2, 0.4, 0.75, 1]) {
        const v = fieldViewport(6, 9, sides, step * Math.PI / 16, sides[count - 1], progress);
        expect(v.cx).toBe(0);
        expect(v.cy).toBe(0);
        expect(v.left).toBe(-v.right);
        expect(v.top).toBe(-v.bottom);
      }
    }
  });

  it('reframes before growing, and ends at the exact stable camera', () => {
    for (let count = 2; count <= 4; count++) {
      const sides = GLASS_ORDER.slice(0, count), building = sides[count - 1];
      const before = fieldViewport(6, 9, sides.slice(0, -1));
      const start = fieldViewport(6, 9, sides, 0, building, 0);
      expect(start.span).toBe(before.span);
      expect(start.cx).toBe(before.cx);
      expect(start.cy).toBe(before.cy);
      const halfway = fieldViewport(6, 9, sides, 0, building, 0.4);
      const end = fieldViewport(6, 9, sides, 0, building, 1);
      expect(halfway.span).toBe(end.span);
      expect(halfway.grow).toBeGreaterThan(0);
      expect(halfway.grow).toBeLessThan(1);
      expect(end).toEqual(fieldViewport(6, 9, sides));
    }
  });

  it('keeps every rotated arm inside the camera, including extreme custom lengths', () => {
    for (const arm of [4, 9, 12]) for (let count = 1; count <= 4; count++) {
      const sides = GLASS_ORDER.slice(0, count);
      for (let step = 0; step <= 16; step++) {
        const angle = step * Math.PI / 8;
        const v = fieldViewport(6, arm, sides, angle);
        for (const side of sides) for (const x of [-3, 3]) for (const y of [-3, -3 - arm]) {
          const turn = angle + side * Math.PI / 2;
          const px = Math.cos(turn) * x - Math.sin(turn) * y;
          const py = Math.sin(turn) * x + Math.cos(turn) * y;
          expect(px).toBeGreaterThanOrEqual(v.left - 1e-8);
          expect(px).toBeLessThanOrEqual(v.right + 1e-8);
          expect(py).toBeGreaterThanOrEqual(v.top - 1e-8);
          expect(py).toBeLessThanOrEqual(v.bottom + 1e-8);
        }
      }
    }
  });

  it('skips camera motion and arm growth when reduced motion is requested', () => {
    expect(fieldViewport(6, 9, [0, 1], 0, 1, 0.1, true)).toEqual(fieldViewport(6, 9, [0, 1]));
  });
});
