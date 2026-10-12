import { describe, expect, it } from 'vitest';
import { Effects } from '../render/effects';
import { newEngine } from './helpers';
import { findMatches } from '../game/matchDetector';
import { computeDrop } from '../game/placement';

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

describe('field recoil', () => {
  it('stays in view and settles during sustained 20 FPS frames', () => {
    const { engine, fx } = setup();
    fx.consume([{ type: 'pieceMoved', side: engine.activeSide, direction: 1, blocked: true }], engine);
    for (let frame = 0; frame < 200; frame++) {
      fx.update(.05, engine);
      expect(Number.isFinite(fx.kickX)).toBe(true);
      expect(Math.abs(fx.kickX)).toBeLessThan(.5);
    }
    expect(fx.kickX).toBe(0);
    expect(fx.kickY).toBe(0);
    expect(fx.settled).toBe(true);
  });

  it('keeps repeated drops and combos bounded through slow and irregular frames', () => {
    const { engine, fx } = setup();
    const piece = engine.activePiece!;
    const placement = computeDrop(engine.board, piece.side, piece.piece, piece.column)!;
    engine.board.paintCenter(['RRRRRR']);
    const match = findMatches(engine.board);
    const frames = [.05, .05, 1 / 60, .033, .25, .05];
    for (let frame = 0; frame < 300; frame++) {
      if (frame % 12 === 0) {
        fx.consume([
          { type: 'pieceMoved', side: engine.activeSide, direction: 1, blocked: true },
          { type: 'pieceLanded', placement, dropped: true },
          { type: 'matchScored', combo: 6, score: 600, match },
        ], engine);
      }
      fx.update(frames[frame % frames.length], engine);
      expect(Math.abs(fx.kickX + fx.shakeX)).toBeLessThan(1);
      expect(Math.abs(fx.kickY + fx.shakeY)).toBeLessThan(1);
      expect(fx.punch).toBeGreaterThanOrEqual(0);
      expect(fx.punch).toBeLessThanOrEqual(.06);
    }
    for (let frame = 0; frame < 60; frame++) fx.update(.05, engine);
    expect(fx.settled).toBe(true);
  });

  it('follows elapsed time regardless of frame rate and freezes at zero delta', () => {
    const { engine, fx: slow } = setup();
    const fast = new Effects();
    fast.reset(engine.activeSide);
    const event = { type: 'pieceMoved' as const, side: engine.activeSide, direction: 1, blocked: true };
    slow.consume([event], engine);
    fast.consume([event], engine);
    slow.update(.2, engine);
    for (let frame = 0; frame < 12; frame++) fast.update(1 / 60, engine);
    expect(slow.kickX).not.toBe(0);
    expect(slow.kickX).toBeCloseTo(fast.kickX, 9);
    const before = slow.kickX;
    slow.update(0, engine);
    expect(slow.kickX).toBe(before);
  });
});

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


describe('disabled decorative effects', () => {
  it('skips bursts and celebrations without changing the board or glass navigation', () => {
    const { fx, engine, turn, play } = setup();
    engine.board.paintCenter(Array.from({ length: 10 }, () => 'RRRRRRRRRR'));
    const match = findMatches(engine.board);
    engine.state.activeMatch = match;
    engine.state.phase = 'clearing';
    fx.explosion = 'off';
    fx.update(.001, engine);
    fx.celebrate(3);
    expect(fx.particles).toHaveLength(0);
    expect(fx.rings).toHaveLength(0);
    expect(fx.flashes).toHaveLength(0);
    expect(fx.veils).toHaveLength(0);
    expect(findMatches(engine.board)).toEqual(match);
    engine.state.phase = 'playing';
    turn(1);
    expect(play(.3).at(-1)).toBeCloseTo(-QUARTER, 9);
  });

  it('clears a running burst immediately when switched off', () => {
    const { fx, engine } = setup();
    engine.board.paintCenter(Array.from({ length: 10 }, () => 'RRRRRRRRRR'));
    engine.state.activeMatch = findMatches(engine.board);
    engine.state.phase = 'clearing';
    fx.update(.001, engine);
    expect(fx.particles.length).toBeGreaterThan(0);
    fx.explosion = 'off';
    expect(fx.particles).toHaveLength(0);
    expect(fx.rings).toHaveLength(0);
    expect(fx.flashes).toHaveLength(0);
    expect(fx.veils).toHaveLength(0);
  });
});
