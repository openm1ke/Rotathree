import { describe, expect, it } from 'vitest';
import { CAMPAIGN, CAMPAIGN_LAST, levelConfig, startsStage } from '../game/campaign';
import { customPlan, DEFAULT_CUSTOM, insanePlan, sanitizeCustom } from '../game/modes';
import { planFor } from '../game/session';
import { GLASS_ORDER } from '../game/config';
import { BOTTOM, LEFT, RIGHT, TOP } from '../game/side';

describe('the campaign', () => {
  it('has fifteen levels: each stage adds colours and starts again from one glass', () => {
    expect(CAMPAIGN).toHaveLength(15);
    expect(CAMPAIGN.map((level) => level.colours)).toEqual([3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 6, 6, 6, 6]);
    expect(CAMPAIGN.map((level) => level.glasses)).toEqual([1, 2, 3, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4]);
    expect(CAMPAIGN.filter((_, i) => startsStage(i)).map((level) => level.glasses)).toEqual([1, 1, 1, 1]);
  });

  it('ends with six colours and three extra glasses', () => {
    const last = CAMPAIGN[CAMPAIGN_LAST];
    expect(last.colours).toBe(6);
    expect(last.glasses).toBe(4);
    expect(levelConfig(last).glassCount).toBe(4);
  });

  it('targets never go down, and the falling only speeds up at the end', () => {
    const targets = CAMPAIGN.map((level) => level.target);
    expect(targets.every((target, i) => i === 0 || target >= targets[i - 1])).toBe(true);
    expect(CAMPAIGN.slice(0, 12).every((level) => level.activeStep === 1 && level.inactiveStep === 3)).toBe(true);
    expect(CAMPAIGN.slice(12).every((level) => level.activeStep < 1 && level.inactiveStep < 3)).toBe(true);
    // Small enough that a first level is short; big enough for a real finish.
    expect(CAMPAIGN[0].target).toBeLessThan(2000);
    expect(CAMPAIGN[CAMPAIGN_LAST].target).toBeGreaterThan(5000);
  });

  it('plans a session from its level', () => {
    const plan = planFor({ mode: 'campaign', level: 4 });
    expect(plan.config.glassCount).toBe(2);
    expect(plan.config.numberOfColors).toBe(4);
    expect(plan.ramp).toBeNull();
  });
});

describe('the other modes', () => {
  it('insane is six colours, four glasses, and speeds up', () => {
    const plan = insanePlan();
    expect(plan.config.numberOfColors).toBe(6);
    expect(plan.config.glassCount).toBe(4);
    expect(plan.ramp?.everyPoints).toBe(1000);
    expect(plan.ramp!.factor).toBeLessThan(1);
  });

  it('custom takes its setup, and speeds up only when asked', () => {
    const plain = customPlan({ ...DEFAULT_CUSTOM, extraGlasses: 0, colours: 9 });
    expect(plain.config.glassCount).toBe(1);
    expect(plain.config.numberOfColors).toBe(9);
    expect(plain.ramp).toBeNull();
    const fast = customPlan({ ...DEFAULT_CUSTOM, speedUp: true, speedUpStep: 0.15, speedUpEvery: 2000 });
    expect(fast.ramp).toMatchObject({ everyPoints: 2000 });
    expect(fast.ramp!.factor).toBeCloseTo(0.85, 9);
  });

  it('a custom setup read back from storage is kept within its limits', () => {
    const cleaned = sanitizeCustom({ extraGlasses: 9, colours: 1, armLength: 40, speedUp: true, speedUpStep: 0.9, gravityScope: 'sideways' });
    expect(cleaned.extraGlasses).toBe(3);
    expect(cleaned.colours).toBe(3);
    expect(cleaned.armLength).toBe(10);
    expect(cleaned.speedUpStep).toBe(0.3);
    expect(cleaned.speedUp).toBe(true);
    expect(cleaned.gravityScope).toBe('wholeGlass');
    expect(sanitizeCustom(undefined)).toEqual(DEFAULT_CUSTOM);
  });

  it('the glasses come into play in the order start, neighbours, opposite', () => {
    expect(GLASS_ORDER).toEqual([TOP, RIGHT, LEFT, BOTTOM]);
  });
});
