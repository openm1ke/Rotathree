import { describe, expect, it } from 'vitest';
import { Effects } from '../render/effects';
import { newEngine } from './helpers';

const QUARTER = Math.PI / 2;

/** An engine and its effects, with the cross taking 0.3 s to a quarter turn. */
const setup = (turnSeconds = 0.3) => {
  const engine = newEngine();
  const fx = new Effects();
  fx.turnSeconds = turnSeconds;
  fx.reset(engine.activeSide);
  const turn = (quarterTurns: number) => {
    engine.switchSide(quarterTurns);
    fx.consume(engine.drainEvents(), engine);
  };
  /** Plays `seconds` of animation in small frames and returns every angle. */
  const play = (seconds: number): number[] => {
    const angles: number[] = [];
    for (let t = 0; t < seconds - 1e-9; t += 0.01) {
      fx.update(0.01, engine);
      angles.push(fx.viewAngle);
    }
    return angles;
  };
  return { engine, fx, turn, play };
};

describe('turning the cross', () => {
  it('eases to the new glass and stops there without swinging past', () => {
    const { fx, turn, play } = setup();
    turn(1);
    const angles = play(0.3);
    // Bringing the glass on the right to the top turns the view anticlockwise.
    expect(angles.at(-1)).toBeCloseTo(-QUARTER, 9);
    for (let i = 1; i < angles.length; i++) {
      expect(angles[i]).toBeLessThanOrEqual(angles[i - 1] + 1e-12);
      expect(angles[i]).toBeGreaterThanOrEqual(-QUARTER - 1e-12);
    }
    // Slow at both ends, fastest in the middle.
    const first = Math.abs(angles[1] - angles[0]);
    const middle = Math.abs(angles[15] - angles[14]);
    const end = Math.abs(angles[29] - angles[28]);
    expect(middle).toBeGreaterThan(first * 2);
    expect(middle).toBeGreaterThan(end * 2);
    expect(play(0.2).every((angle) => Math.abs(angle + QUARTER) < 1e-9)).toBe(true);
    expect(fx.turnMotion).toBe(0);
  });

  it('a turn ordered mid-turn carries on without a jerk', () => {
    const { fx, turn, play } = setup();
    turn(1);
    const before = play(0.15);
    const speedBefore = before.at(-1)! - before.at(-2)!;
    turn(1);
    const after = play(0.6);
    // The first frame after the second order moves about as fast as the last
    // one before it: the speed was carried over, not reset to zero.
    const speedAfter = after[0] - before.at(-1)!;
    expect(Math.abs(speedAfter - speedBefore)).toBeLessThan(Math.abs(speedBefore) * 0.35);
    expect(after.at(-1)).toBeCloseTo(-2 * QUARTER, 9);
    expect(Math.min(...after)).toBeGreaterThanOrEqual(-2 * QUARTER - 1e-12);
    expect(fx.targetTurns).toBe(-2);
  });

  it('a half turn takes longer than a quarter, but not twice as long', () => {
    const { turn, play } = setup();
    turn(2);
    const angles = play(0.45);
    expect(angles[29]).toBeGreaterThan(-2 * QUARTER + 0.05); // not there yet at 0.3 s
    expect(angles.at(-1)).toBeCloseTo(-2 * QUARTER, 9);
  });

  it('with a duration of zero the cross is simply there', () => {
    const { fx, turn, play } = setup(0);
    turn(-1);
    expect(fx.viewAngle).toBeCloseTo(QUARTER, 9);
    expect(play(0.05).every((angle) => Math.abs(angle - QUARTER) < 1e-9)).toBe(true);
    expect(fx.turnMotion).toBe(0);
  });

  it('the grid fades most at the fastest point of the turn', () => {
    const { fx, engine, turn } = setup();
    turn(1);
    fx.update(0.15, engine);
    expect(fx.turnMotion).toBeCloseTo(1, 2);
  });
});

describe('level-up celebration', () => {
  it('throws rings and confetti in the colours in play, then clears up', () => {
    const { fx, engine, play } = setup();
    fx.celebrate(engine.config.numberOfColors);
    expect(fx.rings).toHaveLength(3);
    expect(fx.particles.length).toBeGreaterThan(100);
    play(2.4);
    expect(fx.rings).toHaveLength(0);
    expect(fx.particles).toHaveLength(0);
  });
});
