import { describe, expect, it } from 'vitest';
import { GameEngine } from '../game/engine';
import { defaultConfig } from '../game/config';
import { makePiece } from '../game/piece';
import { TOP } from '../game/side';

const config = { ...defaultConfig, glassCount: 1, seed: 317 };
function check(engine: GameEngine) {
  const restored = new GameEngine(config);
  restored.restoreSnapshot(JSON.parse(JSON.stringify(engine.snapshot())));
  engine.drainEvents();
  expect(restored.snapshot()).toEqual(engine.snapshot());
  for (let i = 0; i < 600 && !engine.isGameOver; i++) {
    if (i % 50 === 0) {
      engine.dropActive();
      restored.dropActive();
    }
    engine.update(0.05);
    restored.update(0.05);
    if (!engine.isGameOver) expect(restored.snapshot()).toEqual(engine.snapshot());
    expect(restored.isGameOver).toBe(engine.isGameOver);
  }
}
describe('local game saves', () => {
  it('keeps an in-flight drop, queued input and future pieces', () => {
    const engine = new GameEngine(config);
    engine.dropActive();
    engine.moveActive(1);
    engine.rotateActive();
    engine.update(0.02);
    check(engine);
  });
  it('does not score a pending match twice', () => {
    const engine = new GameEngine(config);
    engine.incoming.put(TOP, makePiece([0, 0, 0]));
    engine.dropActive();
    engine.update(0.21);
    expect(engine.phase).toBe('matching');
    check(engine);
  });
  it('completes a glass being built exactly once', () => {
    const engine = new GameEngine(config);
    engine.addGlass();
    engine.switchSide(1);
    engine.update(0.5);
    check(engine);
  });
  it('rejects cells outside the cross', () => {
    const engine = new GameEngine(config),
      raw = engine.snapshot();
    raw.board = [[0, 0, 0]];
    expect(() => engine.restoreSnapshot(raw)).toThrow();
  });
});

it('all snapshots in a resolving match are resumable', () => {
  const engine = new GameEngine(config);
  engine.board.paintCenter(['. Y . . . . . . . .', 'B . . . . . . . . .', 'R R . . . . . . . .']);
  engine.incoming.put(TOP, makePiece([0, 1, 2]), { column: 2 });
  engine.dropActive();
  const visited = new Set<string>();
  for (let i = 0; i < 70; i++) {
    visited.add(engine.phase);
    const resumed = new GameEngine(config);
    resumed.restoreSnapshot(JSON.parse(JSON.stringify(engine.snapshot())));
    engine.update(0.05);
    resumed.update(0.05);
    expect(resumed.snapshot()).toEqual(engine.snapshot());
  }
  expect(visited).toEqual(new Set(['pieceDropping', 'matching', 'clearing', 'settling', 'playing']));
});
