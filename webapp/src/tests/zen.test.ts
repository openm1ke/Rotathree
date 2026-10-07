import { describe, expect, it } from 'vitest';
import { zenLevelOf, zenLevelProgress, zenLevelStart, zenLevelTarget } from '../game/zen';

describe('zen levels', () => {
  it('each level asks for a little more than the last', () => {
    expect([1, 2, 3, 4].map(zenLevelTarget)).toEqual([1000, 1500, 2000, 2500]);
    expect([1, 2, 3, 4].map(zenLevelStart)).toEqual([0, 1000, 2500, 4500]);
  });

  it('the level follows the total score', () => {
    expect(zenLevelOf(0)).toBe(1);
    expect(zenLevelOf(999)).toBe(1);
    expect(zenLevelOf(1000)).toBe(2);
    expect(zenLevelOf(2499)).toBe(2);
    expect(zenLevelOf(2500)).toBe(3);
    // One big cascade can carry the score over more than one line.
    expect(zenLevelOf(4600)).toBe(4);
    for (let level = 1; level < 30; level++) {
      expect(zenLevelOf(zenLevelStart(level))).toBe(level);
      expect(zenLevelOf(zenLevelStart(level + 1) - 100)).toBe(level);
    }
  });

  it('progress is counted inside the level and never runs past its target', () => {
    expect(zenLevelProgress(0, 1)).toEqual({ into: 0, target: 1000 });
    expect(zenLevelProgress(1300, 2)).toEqual({ into: 300, target: 1500 });
    // Still shown as level 1 while the cascade that finished it plays out.
    expect(zenLevelProgress(1300, 1)).toEqual({ into: 1000, target: 1000 });
    expect(zenLevelProgress(900, 2)).toEqual({ into: 0, target: 1500 });
  });
});
