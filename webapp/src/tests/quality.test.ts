import { describe, expect, it } from 'vitest';
import { AdaptiveQuality } from '../render/quality';

/** Feeds `frames` frames of `ms` each and reports whether the scale changed. */
const feed = (quality: AdaptiveQuality, ms: number, frames: number): boolean => {
  let changed = false;
  for (let i = 0; i < frames; i++) changed = quality.sample(ms) || changed;
  return changed;
};

const WINDOW = AdaptiveQuality.SETTLE + AdaptiveQuality.WINDOW;

describe('adaptive quality', () => {
  it('stays at full resolution while frames are fast', () => {
    const quality = new AdaptiveQuality();
    expect(feed(quality, 16.7, 2000)).toBe(false);
    expect(quality.scale).toBe(1);
  });

  it('steps down while that makes slow frames faster', () => {
    const quality = new AdaptiveQuality();
    expect(feed(quality, 30, WINDOW)).toBe(true);
    expect(quality.scale).toBe(0.85);
    // Faster, but still slow: one more step.
    expect(feed(quality, 24, WINDOW)).toBe(true);
    expect(quality.scale).toBe(0.7);
    // Fast enough now: it stays where it is.
    expect(feed(quality, 15, WINDOW * 5)).toBe(false);
    expect(quality.scale).toBe(0.7);
  });

  it('takes a step back and gives up when fewer pixels do not help', () => {
    const quality = new AdaptiveQuality();
    // A browser that draws thirty frames a second whatever is drawn.
    expect(feed(quality, 33.3, WINDOW)).toBe(true);
    expect(quality.scale).toBe(0.85);
    expect(feed(quality, 33.3, WINDOW)).toBe(true);
    expect(quality.scale).toBe(1);
    expect(feed(quality, 33.3, WINDOW * 10)).toBe(false);
    expect(quality.scale).toBe(1);
  });

  it('ignores hitches and the frames right after a change', () => {
    const quality = new AdaptiveQuality();
    expect(feed(quality, 500, 1000)).toBe(false);
    expect(quality.scale).toBe(1);
    // A handful of slow frames is not a slow machine.
    feed(quality, 16, AdaptiveQuality.SETTLE);
    feed(quality, 40, 10);
    expect(feed(quality, 16, AdaptiveQuality.WINDOW)).toBe(false);
    expect(quality.scale).toBe(1);
  });

  it('never goes below its lowest level', () => {
    const quality = new AdaptiveQuality();
    let ms = 60;
    for (let step = 0; step < 10; step++) {
      feed(quality, ms, WINDOW);
      ms *= 0.85; // each step helps, but never enough
    }
    expect(quality.scale).toBe(AdaptiveQuality.LEVELS.at(-1));
  });
});
