import { describe, expect, it } from 'vitest';
import { GameEngine } from '../game/engine';
import { BOTTOM, LEFT, RIGHT, TOP } from '../game/side';
import { R, lying, newEngine, runUntilPlaying, testConfig } from './helpers';

describe('a glass added during play', () => {
  it('builds for a while, then its first piece appears at the far end', () => {
    const engine = newEngine({ glassCount: 1 });
    expect([...engine.state.incoming.keys()]).toEqual([TOP]);
    expect(engine.addGlass()).toBe(RIGHT);
    expect(engine.phase).toBe('building');
    expect(engine.addGlass()).toBeNull(); // one at a time
    runUntilPlaying(engine);
    expect(engine.drainEvents()).toContainEqual({ type: 'glassAdded', side: RIGHT });
    expect(engine.sides).toEqual([TOP, RIGHT]);
    expect(engine.state.incoming.get(RIGHT)?.row).toBe(0);
  });

  it('the falling of the other pieces waits while a glass is built', () => {
    const engine = newEngine({ glassCount: 1 });
    engine.addGlass();
    const before = engine.state.incoming.get(TOP)!.stepProgress;
    engine.update(0.5);
    expect(engine.state.incoming.get(TOP)!.stepProgress).toBe(before);
    runUntilPlaying(engine);
    engine.update(0.5);
    expect(engine.state.incoming.get(TOP)!.stepProgress).toBeGreaterThan(before);
  });

  it('a switch made during the building is queued until it is over', () => {
    const engine = newEngine({ glassCount: 1 });
    engine.addGlass();
    engine.switchSide(1);
    expect(engine.activeSide).toBe(TOP);
    runUntilPlaying(engine);
    expect(engine.activeSide).toBe(RIGHT);
  });

  it('a single glass has no side to turn to', () => {
    const engine = newEngine({ glassCount: 1 });
    engine.switchSide(1);
    engine.switchSide(2);
    expect(engine.activeSide).toBe(TOP);
  });

  it('the glasses come into play in order, and the last one is the opposite', () => {
    const engine = newEngine({ glassCount: 2 });
    expect(engine.addGlass()).toBe(LEFT);
    runUntilPlaying(engine);
    expect(engine.addGlass()).toBe(BOTTOM);
    runUntilPlaying(engine);
    expect(engine.addGlass()).toBeNull(); // all four are in play
  });
});

describe('changing the steps', () => {
  it('new step times apply from now on', () => {
    const engine = newEngine();
    engine.setSteps(0.5, 2);
    expect(engine.config.activeStepSeconds).toBe(0.5);
    expect(engine.config.inactiveStepSeconds).toBe(2);
    engine.update(0.5);
    expect(engine.state.incoming.get(TOP)!.row).toBe(1);
  });

  it('a speed ramp steps the falling up as the score passes its interval', () => {
    const engine = newEngine(
      { ...testConfig, numberOfColors: 3 },
      ['R R . . . . . . . .'],
    );
    engine.setRamp({ everyPoints: 100, factor: 0.5, minActive: 0.1, minInactive: 0.2 });
    engine.incoming.take(TOP);
    // Three more red blocks in the floor row make a line of five.
    engine.incoming.put(TOP, lying([R, R, R]), { column: 2, row: 15 });
    engine.dropActive();
    runUntilPlaying(engine);
    expect(engine.state.score).toBe(300);
    expect(engine.state.speedLevel).toBe(3);
    expect(engine.config.activeStepSeconds).toBeCloseTo(0.125, 9);
    expect(engine.config.inactiveStepSeconds).toBeCloseTo(0.375, 9);
    const speedUps = engine.drainEvents().filter((event) => event.type === 'speedUp');
    expect(speedUps).toHaveLength(1);
  });

  it('a ramp never goes below its minimum', () => {
    const engine = new GameEngine({ ...testConfig, activeStepSeconds: 0.3, inactiveStepSeconds: 0.9 });
    engine.setRamp({ everyPoints: 1, factor: 0.1, minActive: 0.2, minInactive: 0.5 });
    engine.board.paintCenter(['R R . . . . . . . .']);
    engine.incoming.take(TOP);
    engine.incoming.put(TOP, lying([R, R, R]), { column: 2, row: 15 });
    engine.dropActive();
    runUntilPlaying(engine);
    expect(engine.config.activeStepSeconds).toBe(0.2);
    expect(engine.config.inactiveStepSeconds).toBe(0.5);
  });

  it('restarting puts the starting steps back', () => {
    const engine = newEngine();
    engine.setSteps(0.25, 0.5);
    engine.restart();
    expect(engine.config.activeStepSeconds).toBe(testConfig.activeStepSeconds);
    expect(engine.board.isEmpty).toBe(true);
  });
});
