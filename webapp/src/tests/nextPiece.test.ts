import { describe, expect, it } from 'vitest';
import { GameEngine } from '../game/engine';
import { defaultConfig } from '../game/config';
import { BOTTOM, LEFT, RIGHT, TOP } from '../game/side';
import { newEngine, runUntilPlaying } from './helpers';

describe('next pieces', () => {
  it('reserves a stable preview per glass regardless of which one locks first', () => {
    const engine = newEngine();
    const next = new Map(engine.sides.map((side) => [side, engine.incoming.nextPieceAt(side)!]));
    const generated = engine.incoming.generator.generated;
    engine.moveActive(1);
    engine.rotateActive();
    engine.switchSide(1);
    for (const side of engine.sides) expect(engine.incoming.nextPieceAt(side)).toBe(next.get(side));
    expect(engine.incoming.generator.generated).toBe(generated);
    for (const side of [RIGHT, BOTTOM, TOP, LEFT]) {
      engine.incoming.take(side);
      expect(engine.incoming.spawn(side, engine.board)!.piece).toBe(next.get(side));
    }
  });

  it('promotes the preview after a hard drop, not while the current piece is in flight', () => {
    const engine = newEngine({ glassCount: 1 });
    const next = engine.incoming.nextPieceAt(TOP)!;
    engine.dropActive();
    expect(engine.incoming.nextPieceAt(TOP)).toBe(next);
    runUntilPlaying(engine);
    expect(engine.activePiece!.piece).toBe(next);
    expect(engine.incoming.nextPieceAt(TOP)).not.toBe(next);
  });

  it('adds a queue when the next campaign glass finishes building', () => {
    const engine = newEngine({ glassCount: 1 });
    const top = engine.incoming.nextPieceAt(TOP);
    engine.addGlass();
    expect(engine.incoming.nextPieceAt(RIGHT)).toBeUndefined();
    runUntilPlaying(engine);
    expect(engine.incoming.nextPieceAt(RIGHT)).toBeDefined();
    expect(engine.incoming.nextPieceAt(TOP)).toBe(top);
  });

  it('preserves all previews and subsequent pieces across save and resume', () => {
    const engine = newEngine(), restored = newEngine();
    restored.restoreSnapshot(JSON.parse(JSON.stringify(engine.snapshot())));
    for (let turn = 0; turn < 12; turn++) {
      const side = engine.sides[turn % engine.sides.length];
      const expected = engine.incoming.nextPieceAt(side);
      expect(restored.incoming.nextPieceAt(side)).toEqual(expected);
      expect(engine.incoming.spawn(side, engine.board)!.piece).toEqual(expected);
      expect(restored.incoming.spawn(side, restored.board)!.piece).toEqual(expected);
      expect(restored.snapshot()).toEqual(engine.snapshot());
    }
  });

  it('migrates old saves without changing the current pieces', () => {
    const engine = newEngine(), restored = newEngine(), again = newEngine();
    const raw = engine.snapshot();
    delete raw.next;
    restored.restoreSnapshot(raw);
    for (const side of engine.sides) {
      expect(restored.incoming.pieceAt(side)!.piece).toEqual(engine.incoming.pieceAt(side)!.piece);
      expect(restored.incoming.nextPieceAt(side)).toBeDefined();
    }
    again.restoreSnapshot(JSON.parse(JSON.stringify(restored.snapshot())));
    expect(again.snapshot()).toEqual(restored.snapshot());
  });

  it('rejects missing, duplicate and inactive preview entries', () => {
    const engine = new GameEngine({ ...defaultConfig, glassCount: 1 });
    const entry = (engine.snapshot().next as object[])[0];
    for (const next of [[], [entry, entry], [{ ...entry, side: RIGHT }]]) {
      expect(() => engine.restoreSnapshot({ ...engine.snapshot(), next })).toThrow();
    }
  });
});
