import { describe, expect, it } from 'vitest';
import { defaultConfig } from '../game/config';
import { GameEngine } from '../game/engine';
import { GlassView } from '../game/glass';
import { fits } from '../game/placement';
import { createRandom } from '../game/random';
import { BOTTOM, LEFT, RIGHT, SIDES, TOP } from '../game/side';
import { ARM, B, DEPTH, G, R, Y, centerAt, lying, newEngine, runUntilPlaying, standing } from './helpers';

describe('four streams', () => {
  it('four pieces exist, staggered so TOP is the furthest along', () => {
    const engine = new GameEngine({ ...defaultConfig, seed: 1 });
    const rows = SIDES.map((side) => engine.state.incoming.get(side)!.row);
    expect(rows[0]).toBeGreaterThan(rows[1]);
    expect(rows[1]).toBeGreaterThan(rows[2]);
    expect(rows[2]).toBeGreaterThan(rows[3]);
    expect(rows[3]).toBe(0);
  });

  it('the active piece steps once a second, the others every three', () => {
    const engine = newEngine();
    engine.update(3);
    expect(engine.state.incoming.get(TOP)!.row).toBe(3);
    for (const side of [RIGHT, BOTTOM, LEFT]) expect(engine.state.incoming.get(side)!.row).toBe(1);
  });

  it('a step is a whole cell: between steps nothing moves', () => {
    const engine = newEngine();
    engine.update(0.9);
    expect(engine.state.incoming.get(TOP)!.row).toBe(0);
    expect(engine.state.incoming.get(TOP)!.stepProgress).toBeCloseTo(0.9, 9);
    expect(engine.state.incoming.get(LEFT)!.stepProgress).toBeCloseTo(0.3, 9);
    engine.update(0.1);
    expect(engine.state.incoming.get(TOP)!.row).toBe(1);
  });

  it('the glass that becomes active speeds up, the one left slows down', () => {
    const engine = newEngine();
    engine.update(1.5);
    const top = engine.state.incoming.get(TOP)!;
    const right = engine.state.incoming.get(RIGHT)!;
    engine.switchSide(1);
    expect(engine.activeSide).toBe(RIGHT);
    expect(top.stepProgress).toBeCloseTo(0.5, 9); // nothing was reset
    engine.update(0.5);
    expect(right.row).toBe(1);
    expect(top.row).toBe(1);
    expect(top.stepProgress).toBeCloseTo(0.5 + 0.5 / 3, 9);
  });

  it('switching goes TOP → RIGHT → BOTTOM → LEFT → TOP, or straight to a side', () => {
    const engine = newEngine();
    for (const expected of [RIGHT, BOTTOM, LEFT, TOP]) {
      engine.switchSide(1);
      expect(engine.activeSide).toBe(expected);
    }
    engine.activateSide(BOTTOM);
    expect(engine.activeSide).toBe(BOTTOM);
    const turns = engine.drainEvents().flatMap((e) => (e.type === 'sideSwitched' ? [e.quarterTurns] : []));
    expect(turns).toEqual([1, 1, 1, 1, 2]);
  });
});

describe('falling and locking', () => {
  it('a piece steps on through the centre, rests one step, then locks', () => {
    const engine = newEngine();
    const piece = engine.incoming.put(TOP, lying([R, B, Y]), { column: 1, row: 14 });
    engine.update(1);
    expect(piece.row).toBe(15);
    engine.update(0.9);
    expect(engine.state.incoming.get(TOP)).toBe(piece);
    expect(engine.board.isEmpty).toBe(true);
    engine.update(0.1);
    expect(engine.board.centerRows().at(-1)).toBe('. R B Y . . . . . .');
    expect(engine.state.selfLocked).toBe(1);
    // A new piece at the far end of the same glass.
    const fresh = engine.state.incoming.get(TOP)!;
    expect(fresh).not.toBe(piece);
    expect(fresh.row).toBe(0);
  });

  it('sliding it off a ledge lets it fall again', () => {
    const engine = newEngine({}, ['. . . . B']);
    const piece = engine.incoming.put(TOP, lying([R, B, Y]), { column: 3, row: 14 });
    engine.update(0.5);
    engine.moveActive(2);
    engine.update(0.5);
    expect(engine.state.incoming.get(TOP)).toBe(piece);
    expect(piece.row).toBe(15);
  });

  it('an inactive piece falls along its own axis; the view stays put', () => {
    const engine = newEngine();
    engine.incoming.put(RIGHT, lying([R, B, Y]), { column: 0, row: 14 });
    engine.update(6);
    expect(engine.activeSide).toBe(TOP);
    expect([0, 1, 2].map((row) => centerAt(engine.board, row, 0))).toEqual([R, B, Y]);
  });

  it('a piece coming up under the pile locks inside its own arm', () => {
    const engine = newEngine({}, ['. . . . . . R B Y .']);
    engine.incoming.put(BOTTOM, lying([Y, Y, B]), { column: 1, row: 4 });
    engine.update(6);
    expect([engine.board.at(16, 14), engine.board.at(16, 13), engine.board.at(16, 12)]).toEqual([Y, Y, B]);
    expect(engine.isGameOver).toBe(false);
  });

  it('pieces of two glasses pass through each other until one locks', () => {
    const engine = newEngine();
    engine.board.set(13, 12, G);
    const top = engine.incoming.put(TOP, lying([R, R, Y]), { column: 3, row: 12 });
    engine.incoming.put(LEFT, standing([B, Y, B]), { column: 2, row: 9, stepProgress: 0.5 });
    engine.update(1.2);
    expect(top.row).toBe(13);
    engine.update(0.4);
    expect([engine.board.at(13, 9), engine.board.at(13, 10), engine.board.at(13, 11)]).toEqual([B, Y, B]);
    expect(top.row).toBe(12); // put back on top of the new blocks
    engine.update(0.5);
    expect([engine.board.at(12, 9), engine.board.at(12, 10), engine.board.at(12, 11)]).toEqual([R, R, Y]);
  });

  it('the countdown is the steps left plus the one it locks on', () => {
    const engine = newEngine();
    engine.incoming.put(TOP, lying([R, B, Y]), { row: 13 });
    engine.incoming.put(RIGHT, lying([R, B, Y]), { row: 13 });
    expect(engine.secondsToLock(TOP)).toBeCloseTo(3, 9);
    expect(engine.secondsToLock(RIGHT)).toBeCloseTo(9, 9);
  });
});

describe('controlling the active piece', () => {
  it('moves are stopped by the walls and by settled blocks', () => {
    const engine = newEngine();
    const piece = engine.incoming.put(TOP, lying([R, B, Y]), { column: 3, row: 10 });
    engine.moveActive(-10);
    expect(piece.column).toBe(0);
    engine.moveActive(99);
    expect(piece.column).toBe(7);
    engine.board.set(ARM + 4, ARM + 3, B); // glass row 10, lane 3
    piece.column = 5;
    engine.moveActive(-3);
    expect(piece.column).toBe(4);
    const blocked = engine.drainEvents().filter((e) => e.type === 'pieceMoved' && e.blocked);
    expect(blocked).toHaveLength(3);
  });

  it('rotates through all four orientations around the middle square', () => {
    const engine = newEngine();
    const piece = engine.incoming.put(TOP, lying([R, B, Y]), { column: 3, row: 5 });
    const seen: [number, number, number][] = [];
    for (let i = 0; i < 4; i++) {
      engine.rotateActive();
      seen.push([piece.piece.orientation, piece.column, piece.row]);
    }
    expect(seen).toEqual([
      [1, 4, 4],
      [2, 3, 5],
      [3, 4, 4],
      [0, 3, 5],
    ]);
    engine.rotateActive(false);
    expect(piece.piece.orientation).toBe(3);
  });

  it('each orientation lands with its colours that way round', () => {
    const landed = (turns: number) => {
      const engine = newEngine();
      engine.incoming.put(TOP, lying([R, B, Y]), { column: 3, row: 5 });
      for (let i = 0; i < turns; i++) engine.rotateActive();
      engine.dropActive();
      runUntilPlaying(engine);
      return engine.board.centerRows().slice(7);
    };
    expect(landed(0).at(-1)).toBe('. . . R B Y . . . .');
    expect(landed(1).map((row) => row[8])).toEqual(['R', 'B', 'Y']);
    expect(landed(2).at(-1)).toBe('. . . Y B R . . . .');
    expect(landed(3).map((row) => row[8])).toEqual(['Y', 'B', 'R']);
  });

  it('with no room to turn it stays as it is', () => {
    const engine = newEngine();
    const glass = new GlassView(engine.board, TOP);
    for (let row = 8; row <= 14; row++) {
      glass.set(row, 3, row % 2 === 0 ? R : B);
      glass.set(row, 5, row % 2 === 0 ? B : R);
    }
    const piece = engine.incoming.put(TOP, standing([Y, Y, B]), { column: 4, row: 10 });
    engine.rotateActive();
    expect([piece.piece.orientation, piece.column, piece.row]).toEqual([1, 4, 10]);
    expect(engine.drainEvents().some((e) => e.type === 'pieceRotated' && e.blocked)).toBe(true);
  });

  it('hard drop is a short timed flight to where the preview said', () => {
    const engine = newEngine({}, ['. . . B', '. . R B']);
    engine.incoming.put(TOP, lying([Y, Y, R]), { column: 1, row: 2 });
    const preview = engine.previewDrop(TOP)!;
    engine.dropActive();
    expect(engine.phase).toBe('pieceDropping');
    expect(engine.state.incoming.has(TOP)).toBe(false);
    expect(runUntilPlaying(engine)).toEqual(['pieceDropping', 'playing']);
    for (const cell of preview.cells) expect(engine.board.at(cell.row, cell.col)).toBe(cell.color);
    expect(engine.state.selfLocked).toBe(0);
  });

  it('soft drop speeds up the fall but not the wait before locking', () => {
    const engine = newEngine({ softDropStepSeconds: 0.05 });
    const piece = engine.incoming.put(TOP, lying([R, B, Y]), { column: 0, row: 5 });
    engine.setSoftDrop(true);
    engine.update(0.5);
    expect(piece.row).toBe(15); // ten rows in half a second
    engine.update(0.5);
    expect(engine.state.incoming.get(TOP)).toBe(piece); // still there
    engine.update(0.6);
    expect(engine.board.centerRows().at(-1)).toBe('R B Y . . . . . . .');
  });

  it('input during a drop is queued and replayed in order', () => {
    const engine = newEngine({ maxQueuedInputs: 3 });
    engine.incoming.put(TOP, lying([R, B, Y]), { column: 0 });
    engine.incoming.put(RIGHT, lying([B, B, Y]), { column: 3, row: 2 });
    engine.dropActive();
    engine.switchSide(1);
    engine.moveActive(-3);
    engine.rotateActive();
    engine.switchSide(1); // over the limit of three: dropped
    expect(engine.activeSide).toBe(TOP);
    runUntilPlaying(engine);
    expect(engine.activeSide).toBe(RIGHT);
    const piece = engine.state.incoming.get(RIGHT)!;
    expect([piece.piece.orientation, piece.column]).toEqual([1, 1]);
  });
});

describe('matches inside the engine', () => {
  it('dropping the piece that starts a cascade reaches combo 2', () => {
    const engine = newEngine({}, ['B B R B']);
    engine.incoming.put(TOP, standing([B, R, R]), { column: 2 });
    engine.dropActive();
    expect(runUntilPlaying(engine)).toEqual([
      'pieceDropping', 'matching', 'clearing', 'settling', 'cascading', 'clearing', 'playing',
    ]);
    expect(engine.state.bestCombo).toBe(2);
    expect(engine.state.score).toBe(500);
    expect(engine.state.matches).toBe(2);
    expect(engine.board.isEmpty).toBe(true);
    const events = engine.drainEvents();
    expect(events.flatMap((e) => (e.type === 'matchScored' ? [e.combo] : []))).toEqual([1, 2]);
    expect(events.flatMap((e) => (e.type === 'cellsPopped' ? [e.cells.length] : []))).toEqual([3, 4]);
  });

  it('after a turn, blocks fall relative to the new down', () => {
    const engine = newEngine();
    engine.board.set(ARM + 4, ARM + 5, Y);
    const before = engine.board.clone();
    engine.switchSide(1);
    expect(engine.board.equals(before)).toBe(true); // turning moves nothing
    engine.incoming.put(RIGHT, lying([R, R, R]), { column: 7 });
    engine.dropActive();
    runUntilPlaying(engine);
    expect(engine.state.matches).toBe(1);
    expect(centerAt(engine.board, 4, 0)).toBe(Y);
  });

  it('falling pieces stand still while a match resolves, unless told not to', () => {
    const gained = (pause: boolean) => {
      const engine = newEngine({ pauseIncomingDuringCascade: pause });
      engine.incoming.put(TOP, lying([R, R, R]));
      engine.dropActive();
      while (engine.phase === 'pieceDropping') engine.update(0.002);
      const before = engine.state.incoming.get(RIGHT)!.stepProgress;
      runUntilPlaying(engine);
      return engine.state.incoming.get(RIGHT)!.stepProgress - before;
    };
    expect(gained(true)).toBeCloseTo(0, 2);
    expect(gained(false)).toBeGreaterThan(0.1);
  });
});

describe('game over', () => {
  const fillLane = (engine: GameEngine, side: 0 | 1 | 2 | 3, topRow: number) => {
    const glass = new GlassView(engine.board, side);
    for (let row = topRow; row < DEPTH; row++) glass.set(row, 4, row % 2 === 0 ? R : B);
  };

  it('a glass filled up to the far end of its arm ends the game', () => {
    const engine = newEngine();
    fillLane(engine, TOP, 1);
    engine.incoming.put(TOP, lying([Y, Y, B]), { column: 3 });
    expect(engine.headroom(TOP)).toBe(1);
    expect(engine.isCrowded(TOP)).toBe(true);
    engine.update(1.1);
    expect(engine.phase).toBe('gameOver');
    expect(engine.state.gameOverSide).toBe(TOP);
  });

  it('an inactive glass that overflows ends the game too', () => {
    const engine = newEngine();
    fillLane(engine, RIGHT, 1);
    engine.incoming.put(RIGHT, lying([Y, Y, B]), { column: 3 });
    engine.update(3.1);
    expect(engine.state.gameOverSide).toBe(RIGHT);
  });

  it('moving out of the full lanes in time avoids it; nothing happens after', () => {
    const engine = newEngine();
    fillLane(engine, TOP, 1);
    engine.incoming.put(TOP, lying([Y, Y, B]), { column: 3 });
    engine.moveActive(2);
    engine.dropActive();
    runUntilPlaying(engine);
    expect(engine.isGameOver).toBe(false);

    const lost = newEngine();
    fillLane(lost, TOP, 1);
    lost.incoming.put(TOP, lying([Y, Y, B]), { column: 3 });
    lost.update(1.1);
    const elapsed = lost.state.elapsedSeconds;
    lost.switchSide(1);
    lost.update(3);
    expect(lost.activeSide).toBe(TOP);
    expect(lost.state.elapsedSeconds).toBe(elapsed);
    lost.restart();
    expect(lost.phase).toBe('playing');
    expect(lost.board.isEmpty).toBe(true);
  });
});

describe('determinism', () => {
  const play = (step: number) => {
    const engine = new GameEngine({ ...defaultConfig, seed: 5 });
    for (let t = 0; t < 60 - 1e-9 && !engine.isGameOver; t += step) engine.update(step);
    return engine;
  };

  it('how the frame time is sliced does not change the game', () => {
    const coarse = play(0.25);
    const fine = play(0.0125);
    expect(coarse.board.equals(fine.board)).toBe(true);
    expect(coarse.state.piecesPlaced).toBe(fine.state.piecesPlaced);
    expect(coarse.state.piecesPlaced).toBeGreaterThan(0);
  });

  it('random play keeps the engine consistent', () => {
    for (let seed = 0; seed < 12; seed++) {
      const engine = new GameEngine({
        ...defaultConfig,
        seed,
        activeStepSeconds: 0.3,
        inactiveStepSeconds: 0.6,
        settleAfterBoardRotation: seed % 2 === 1,
        gravityScope: seed % 3 === 0 ? 'aboveCleared' : 'wholeGlass',
      });
      const random = createRandom(seed);
      for (let step = 0; step < 4000 && !engine.isGameOver; step++) {
        const roll = Math.floor(random() * 10);
        if (roll === 0) engine.switchSide(random() < 0.5 ? 1 : -1);
        else if (roll === 1) engine.moveActive(Math.floor(random() * 9) - 4);
        else if (roll === 2) engine.rotateActive(random() < 0.5);
        else if (roll === 3) engine.dropActive();
        else if (roll === 4) engine.setSoftDrop(random() < 0.5);
        engine.update(random() * 0.08);

        const state = engine.state;
        for (const piece of state.incoming.values()) {
          expect(fits(state.board, piece.side, piece.piece, piece.row, piece.column)).toBe(true);
        }
        expect(state.board.blockCount).toBe(
          state.piecesPlaced * 3 - state.clearedCells + (state.activeMatch?.cells.size ?? 0),
        );
        if (state.phase === 'playing') expect(state.incoming.size).toBe(4);
      }
      expect(engine.state.piecesPlaced).toBeGreaterThan(0);
    }
  });
});
