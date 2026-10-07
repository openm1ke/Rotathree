import { describe, expect, it } from 'vitest';
import { Board, EMPTY } from '../game/board';
import { resolveCascade } from '../game/cascade';
import { defaultConfig, glassDepth, gridSize, scoreForRun } from '../game/config';
import { PieceGenerator } from '../game/generator';
import { GlassView, sideAtSlot, slotOfSide, viewToWorld, worldToView } from '../game/glass';
import { settle } from '../game/gravity';
import { findMatches } from '../game/matchDetector';
import { isHorizontal, pieceOffsets, rotatePiece, samePiece } from '../game/piece';
import { computeDrop, headroom, landingRow } from '../game/placement';
import { BOTTOM, LEFT, RIGHT, SIDES, TOP, stepsTo, turned } from '../game/side';
import { ARM, B, DEPTH, G, R, Y, boardOf, centerAt, emptyBoard, lying, standing, testConfig } from './helpers';

describe('piece', () => {
  it('four quarter turns bring the first colour left, top, right, bottom', () => {
    let piece = lying([R, B, Y]);
    const first: { row: number; col: number }[] = [];
    const shapes: boolean[] = [];
    for (let i = 0; i < 4; i++) {
      first.push(pieceOffsets(piece)[0]);
      shapes.push(isHorizontal(piece));
      piece = rotatePiece(piece);
    }
    expect(first).toEqual([
      { row: 0, col: 0 },
      { row: 0, col: 0 },
      { row: 0, col: 2 },
      { row: 2, col: 0 },
    ]);
    expect(shapes).toEqual([true, false, true, false]);
    expect(samePiece(piece, lying([R, B, Y]))).toBe(true);
  });

  it('turning back undoes a turn, and the squares are never rearranged', () => {
    const piece = lying([R, R, B]);
    expect(samePiece(rotatePiece(rotatePiece(piece), false), piece)).toBe(true);
    expect(rotatePiece(piece, false).orientation).toBe(3);
    let turnedPiece = piece;
    for (let i = 0; i < 7; i++) {
      turnedPiece = rotatePiece(turnedPiece);
      expect(turnedPiece.colors).toEqual([R, R, B]);
    }
  });

  it('the generator is deterministic and keeps to the palette', () => {
    const a = new PieceGenerator({ ...defaultConfig, seed: 42 });
    const b = new PieceGenerator({ ...defaultConfig, seed: 42 });
    for (let i = 0; i < 100; i++) {
      const piece = a.next();
      expect(samePiece(piece, b.next())).toBe(true);
      expect(piece.colors).toHaveLength(3);
      expect(piece.colors.every((color) => color < 3)).toBe(true);
    }
    const four = new PieceGenerator({ ...defaultConfig, seed: 3, numberOfColors: 4 });
    const seen = new Set<number>();
    for (let i = 0; i < 300; i++) four.next().colors.forEach((color) => seen.add(color));
    expect([...seen].sort()).toEqual([0, 1, 2, 3]);
  });

  it('single-colour sticks are rarer than a fair roll', () => {
    const mono = (keep: number) => {
      const generator = new PieceGenerator({ ...defaultConfig, seed: 11, monoPieceKeepChance: keep });
      let count = 0;
      for (let i = 0; i < 3000; i++) if (new Set(generator.next().colors).size === 1) count++;
      return count;
    };
    expect(mono(1)).toBeGreaterThan(250);
    expect(mono(0.4)).toBeLessThan(mono(1) * 0.6);
    expect(mono(0)).toBe(0);
  });
});

describe('the cross and its glasses', () => {
  it('the default field is a 10×10 centre with arms of nine cells', () => {
    expect(gridSize(defaultConfig)).toBe(28);
    expect(glassDepth(defaultConfig)).toBe(19);
  });

  it('has a centre, four arms and no corners', () => {
    const board = emptyBoard();
    expect(board.size).toBe(22);
    let inside = 0;
    for (let row = 0; row < board.size; row++) {
      for (let col = 0; col < board.size; col++) if (board.isInside(row, col)) inside++;
    }
    expect(inside).toBe(100 + 4 * 60);
    expect(board.isInside(0, 0)).toBe(false);
    expect(board.isInside(5, 5)).toBe(false);
    expect(board.isInside(0, 10)).toBe(true);
    expect(board.isCenter(0, 10)).toBe(false);
    expect(board.isCenter(6, 6)).toBe(true);
  });

  it('row 0 of a glass is the far end of its own arm, the last row its floor', () => {
    const board = emptyBoard();
    expect(new GlassView(board, TOP).toWorld(0, 0)).toEqual({ row: 0, col: 6 });
    expect(new GlassView(board, RIGHT).toWorld(0, 0)).toEqual({ row: 6, col: 21 });
    expect(new GlassView(board, BOTTOM).toWorld(0, 0)).toEqual({ row: 21, col: 15 });
    expect(new GlassView(board, LEFT).toWorld(0, 0)).toEqual({ row: 15, col: 0 });
    for (let lane = 0; lane < 10; lane++) {
      expect(new GlassView(board, TOP).toWorld(DEPTH - 1, lane).row).toBe(15);
      expect(new GlassView(board, RIGHT).toWorld(DEPTH - 1, lane).col).toBe(6);
      expect(new GlassView(board, BOTTOM).toWorld(DEPTH - 1, lane).row).toBe(6);
      expect(new GlassView(board, LEFT).toWorld(DEPTH - 1, lane).col).toBe(15);
    }
  });

  it('the centre is shared by all four glasses, each arm belongs to one', () => {
    const board = emptyBoard();
    for (const side of SIDES) {
      const glass = new GlassView(board, side);
      for (let row = 0; row < glass.depth; row++) {
        for (let lane = 0; lane < glass.lanes; lane++) {
          const world = glass.toWorld(row, lane);
          expect(board.isInside(world.row, world.col)).toBe(true);
          expect(board.isCenter(world.row, world.col)).toBe(row >= ARM);
          expect(glass.fromWorld(world.row, world.col)).toEqual({ row, lane });
        }
      }
    }
    expect(new GlassView(board, TOP).fromWorld(10, 0)).toBeNull();
  });

  it('view ↔ world round-trips and maps the cross onto itself', () => {
    const board = emptyBoard();
    for (const side of SIDES) {
      for (let row = 0; row < board.size; row++) {
        for (let col = 0; col < board.size; col++) {
          const world = viewToWorld(row, col, side, board.size);
          expect(worldToView(world.row, world.col, side, board.size)).toEqual({ row, col });
          expect(board.isInside(world.row, world.col)).toBe(board.isInside(row, col));
        }
      }
    }
  });

  it('sides turn TOP → RIGHT → BOTTOM → LEFT → TOP', () => {
    expect(turned(TOP, 1)).toBe(RIGHT);
    expect(turned(LEFT, 1)).toBe(TOP);
    expect(turned(TOP, -1)).toBe(LEFT);
    expect(stepsTo(BOTTOM, RIGHT)).toBe(-1);
    expect(stepsTo(BOTTOM, TOP)).toBe(2);
    expect(sideAtSlot(RIGHT, RIGHT)).toBe(BOTTOM);
    for (const active of SIDES) {
      for (const side of SIDES) expect(sideAtSlot(active, slotOfSide(active, side))).toBe(side);
    }
  });
});

describe('placement', () => {
  const floor = DEPTH - 1;

  it('a stick falls through the arm and the centre to the floor', () => {
    const placement = computeDrop(emptyBoard(), TOP, lying([R, B, Y]), 3)!;
    expect(placement.row).toBe(floor);
    expect(placement.cells).toEqual([
      { row: ARM + 9, col: ARM + 3, color: R },
      { row: ARM + 9, col: ARM + 4, color: B },
      { row: ARM + 9, col: ARM + 5, color: Y },
    ]);
  });

  it('rests on the highest block under it and never passes a floating one', () => {
    const board = boardOf(['. . . . B', '. . . R B']);
    expect(landingRow(board, TOP, lying([R, B, Y]), 2)).toBe(floor - 2);
    const floating = emptyBoard();
    floating.set(ARM + 4, ARM + 5, B);
    expect(landingRow(floating, TOP, lying([R, B, Y]), 4)).toBe(ARM + 3);
  });

  it('pieces of the other glasses fly to the far wall of the centre', () => {
    const right = computeDrop(emptyBoard(), RIGHT, lying([R, B, Y]), 0)!;
    expect(right.cells.map((c) => [c.row - ARM, c.col - ARM])).toEqual([[0, 0], [1, 0], [2, 0]]);
    const bottom = computeDrop(emptyBoard(), BOTTOM, lying([R, B, Y]), 0)!;
    expect(bottom.cells.map((c) => [c.row - ARM, c.col - ARM])).toEqual([[0, 9], [0, 8], [0, 7]]);
    const left = computeDrop(emptyBoard(), LEFT, lying([R, B, Y]), 0)!;
    expect(left.cells.map((c) => [c.row - ARM, c.col - ARM])).toEqual([[9, 9], [8, 9], [7, 9]]);
  });

  it('a pile on the floor is met from below inside the bottom arm', () => {
    const board = boardOf(['R B Y']);
    const placement = computeDrop(board, BOTTOM, lying([Y, Y, B]), 7)!;
    expect(placement.row).toBe(ARM - 1);
    expect(placement.cells.every((cell) => !board.isCenter(cell.row, cell.col))).toBe(true);
    expect(landingRow(board, BOTTOM, lying([Y, Y, B]), 3)).toBe(floor);
  });

  it('headroom is the free rows at the far end; zero means no room', () => {
    const board = emptyBoard();
    expect(headroom(board, TOP, 3, 3)).toBe(DEPTH);
    board.set(0, ARM + 4, R);
    expect(headroom(board, TOP, 3, 3)).toBe(0);
    expect(computeDrop(board, TOP, lying([R, B, Y]), 3)).toBeNull();
  });
});

describe('matches', () => {
  it('finds horizontal and vertical lines of three or more', () => {
    expect(findMatches(boardOf(['B R R R Y'])).cells.size).toBe(3);
    expect(findMatches(boardOf(['Y', 'Y', 'Y', 'B'])).runs[0].horizontal).toBe(false);
    expect(findMatches(boardOf(['B B B B'])).runs[0].cells).toHaveLength(4);
  });

  it('crossing lines share their common cell once', () => {
    const result = findMatches(boardOf(['. R .', '. R .', 'B R B', 'R R R']));
    expect(result.runs).toHaveLength(2);
    expect(result.cells.size).toBe(6);
  });

  it('ignores different colours, pairs, gaps and diagonals', () => {
    expect(findMatches(boardOf(['R B R B Y R'])).runs).toHaveLength(0);
    expect(findMatches(boardOf(['R R B B Y Y'])).runs).toHaveLength(0);
    expect(findMatches(boardOf(['R R . R R'])).runs).toHaveLength(0);
    expect(findMatches(boardOf(['R . .', 'B R .', 'Y B R'])).runs).toHaveLength(0);
  });

  it('a line may lie in an arm or cross into the centre', () => {
    const board = emptyBoard();
    board.set(4, 10, Y);
    board.set(5, 10, Y);
    board.set(6, 10, Y);
    board.set(10, 4, R);
    board.set(10, 5, R);
    board.set(10, 6, R);
    expect(findMatches(board).runs).toHaveLength(2);
  });
});

describe('gravity', () => {
  it('blocks fall to the floor, keep their order and close gaps', () => {
    const board = boardOf(['B . Y', '. . .', 'Y R .', '. . .', 'R . B']);
    settle(board, TOP);
    expect(board.centerRows().slice(7)).toEqual([
      'B . . . . . . . . .',
      'Y . Y . . . . . . .',
      'R R B . . . . . . .',
    ]);
  });

  it('down follows the active side', () => {
    const fallen = (side: 0 | 1 | 2 | 3) => {
      const board = emptyBoard();
      board.set(ARM + 4, ARM + 5, R);
      settle(board, side);
      return board;
    };
    expect(centerAt(fallen(TOP), 9, 5)).toBe(R);
    expect(centerAt(fallen(RIGHT), 4, 0)).toBe(R);
    expect(centerAt(fallen(BOTTOM), 0, 5)).toBe(R);
    expect(centerAt(fallen(LEFT), 4, 9)).toBe(R);
  });

  it('the active arm drains into the centre; the other arms stay put', () => {
    const board = emptyBoard();
    board.set(1, ARM + 4, R); // top arm
    board.set(10, 2, G); // left arm
    board.set(19, 10, Y); // bottom arm, below the floor
    const moves = settle(board, TOP);
    expect(moves).toHaveLength(1);
    expect(centerAt(board, 9, 4)).toBe(R);
    expect(board.at(10, 2)).toBe(G);
    expect(board.at(19, 10)).toBe(Y);
  });

  it('aboveCleared only releases blocks over a popped cell', () => {
    const board = emptyBoard();
    board.set(ARM + 2, ARM + 3, R);
    board.set(ARM + 2, ARM + 6, B);
    const cleared = new Set([board.index(ARM + 5, ARM + 3)]);
    expect(settle(board, TOP, 'aboveCleared', cleared)).toHaveLength(1);
    expect(centerAt(board, 9, 3)).toBe(R);
    expect(centerAt(board, 2, 6)).toBe(B);
  });
});

describe('cascade and scoring', () => {
  it('longer lines and higher combos are worth more', () => {
    expect(scoreForRun(testConfig, 3, 1)).toBe(100);
    expect(scoreForRun(testConfig, 4, 1)).toBe(200);
    expect(scoreForRun(testConfig, 5, 1)).toBe(300);
    expect(scoreForRun(testConfig, 3, 2)).toBe(200);
    expect(scoreForRun(testConfig, 2, 1)).toBe(0);
  });

  it('match → pop → fall → second match gives combo 2', () => {
    const board = boardOf(['. . B .', '. . R .', '. . R .', 'B B R B']);
    const steps = resolveCascade(board, TOP, testConfig);
    expect(steps.map((step) => step.combo)).toEqual([1, 2]);
    expect(steps[0].score).toBe(100);
    expect(steps[1].score).toBe(400);
    expect(board.isEmpty).toBe(true);
  });

  it('a stable board resolves to nothing', () => {
    const board = boardOf(['R B R', 'B R B']);
    expect(resolveCascade(board, TOP, testConfig)).toHaveLength(0);
    expect(board.blockCount).toBe(6);
    expect(new Board(10, ARM).at(0, 10)).toBe(EMPTY);
    expect(standing([R, B, Y]).orientation).toBe(1);
  });
});
