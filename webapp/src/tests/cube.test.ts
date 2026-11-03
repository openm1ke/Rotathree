import { describe, expect, it } from 'vitest';
import { CubeGame, EMPTY, SIDES, type Vec } from '../cube/rules';
import { CUBE_LESSON_LAST, lessonGame } from '../cube/tutorial';

const run = (game: CubeGame, seconds: number) => {
  for (let t = 0; t < seconds; t += 0.02) game.update(0.02);
};
const sideOf = (axis: number, sign: 1 | -1) => SIDES.findIndex((s) => s.axis === axis && s.sign === sign);
const FRONT = sideOf(2, 1);
const BACK = sideOf(2, -1);
const LEFT = sideOf(0, -1);
const RIGHT = sideOf(0, 1);

describe('Cube: the picture is the board', () => {
  it('stops the stick on top on a block seen behind it', () => {
    const game = new CubeGame({ seed: 4, inactiveFalls: false });
    const h = game.half;
    game.hub.set(game.cellAt(0, -h, -2), 1);
    const top = game.activePiece!;
    top.pivot = game.cellAt(0, h, 0);
    top.dir = [1, 0, 0];
    expect(game.screenOf(game.restRow(top))[1]).toBe(-h + 1);
  });

  it('pops a line of what is seen, whatever the depths, and not one broken by a nearer block', () => {
    const game = new CubeGame({ seed: 5, inactiveFalls: false });
    const h = game.half;
    game.hub.set(game.cellAt(-1, -h, 2), 3);
    game.hub.set(game.cellAt(0, -h, -3), 3);
    game.hub.set(game.cellAt(1, -h, 0), 3);
    game.hub.set(game.cellAt(0, -h, -1), 2);
    expect(game.findMatches().runs).toHaveLength(0);
    game.hub.set(game.cellAt(0, -h, -1), EMPTY);
    const match = game.findMatches();
    expect(match.runs).toHaveLength(1);
    expect(match.cells.size).toBe(3);
  });

  it('lets a cell of the picture fall with everything behind it', () => {
    const game = new CubeGame({ seed: 6, inactiveFalls: false });
    const h = game.half;
    game.hub.set(game.cellAt(0, -h, 1), 0);
    game.hub.set(game.cellAt(0, -h, -2), 1);
    game.hub.set(game.cellAt(0, -h + 2, 3), 2);
    game.hub.set(game.cellAt(0, -h + 2, -1), 4);
    expect(game.settle()).toHaveLength(2);
    expect(game.hub.at(game.cellAt(0, -h + 1, 3))).toBe(2);
    expect(game.hub.at(game.cellAt(0, -h + 1, -1))).toBe(4);
  });
});

describe('Cube: tipping the hub over', () => {
  // ↑: data −Z comes on top; data +Y now looks at the eye.
  const tipUp = (game: CubeGame) =>
    game.turn(sideOf(2, -1), [0, 1, 0], { right: [1, 0, 0], up: [0, 0, -1] }, true);

  it('shows the tops of the old columns as the bottom line', () => {
    const game = new CubeGame({ seed: 7, inactiveFalls: false });
    game.pieces.clear();
    const h = game.half;
    for (let sy = -h; sy < -h + 3; sy++) game.hub.set(game.cellAt(-1, sy, 0), sy + h);
    game.hub.set(game.cellAt(1, -h, 0), 3);
    tipUp(game);
    run(game, 1);
    const seen = (sx: number) => {
      const p = game.seenAt(sx, -h);
      return p ? game.hub.at(p) : null;
    };
    expect(seen(-1)).toBe(2);
    expect(seen(1)).toBe(3);
  });

  it('keeps the sticks on its axis where the screen showed them, and moves none on a turn in the screen', () => {
    const game = new CubeGame({ seed: 5, inactiveFalls: false });
    const left = game.pieces.get(LEFT)!;
    left.pivot = game.cellAt(-9, 1, 0);
    left.dir = [1, 0, 0];
    const right = game.pieces.get(RIGHT)!;
    const before = [game.screenOf(left.pivot), game.screenOf(right.pivot)];
    tipUp(game);
    expect([game.screenOf(left.pivot), game.screenOf(right.pivot)]).toEqual(before);
    expect([left.dir[0], left.dir[2] + 0]).toEqual([1, 0]);

    const other = new CubeGame({ seed: 6, inactiveFalls: false });
    const snapshot = () => [...other.pieces.values()].map((p) => `${p.pivot}|${p.dir}`).join(' ');
    const was = snapshot();
    other.turn(LEFT, [0, 0, 1], { right: [0, 1, 0], up: [-1, 0, 0] }, false);
    expect(snapshot()).toBe(was);
  });

  it('previews a tip without touching the game, and counts what would pop', () => {
    const game = new CubeGame({ seed: 7, inactiveFalls: false });
    game.pieces.clear();
    const h = game.half;
    for (let sy = -h; sy < -h + 3; sy++) game.hub.set(game.cellAt(-1, sy, 0), 0);
    game.hub.set(game.cellAt(0, -h, 0), 0);
    game.hub.set(game.cellAt(1, -h, 0), 0);
    const version = game.hub.version;
    const preview = game.previewTurn([0, 1, 0], { right: [1, 0, 0], up: [0, 0, -1] });
    expect(game.hub.version).toBe(version);
    expect(preview.rounds).toBeGreaterThanOrEqual(1);
    expect(preview.popped).toBeGreaterThanOrEqual(3);
  });
});

describe('Cube: the glasses in front and behind', () => {
  it('lands a front stick in front, seen, and a back one behind, hidden', () => {
    const game = new CubeGame({ seed: 8, inactiveFalls: false });
    for (const sx of [-1, 0, 1]) game.hub.set(game.cellAt(sx, 0, 0), 1);
    game.pieces.get(FRONT)!.pivot = game.cellAt(0, 0, game.middle);
    game.pieces.get(BACK)!.pivot = game.cellAt(0, 0, -game.middle);
    expect(game.landing(FRONT)).toMatchObject({ layer: 1, count: 3 });
    expect(game.landing(BACK)).toMatchObject({ layer: -1, count: 0 });
  });

  it('waits until steered unless they may fall alone', () => {
    const game = new CubeGame({ seed: 3 });
    const start: Vec = [...game.pieces.get(FRONT)!.pivot];
    run(game, 7);
    expect(game.pieces.get(FRONT)!.pivot).toEqual(start);
    game.config.depthFalls = true;
    run(game, 6.5);
    expect(game.pieces.get(FRONT)!.pivot[2]).toBe(start[2] - 1);
  });

  it('steers them in place', () => {
    const game = new CubeGame({ seed: 3, inactiveFalls: false });
    game.control(FRONT);
    const start: Vec = [...game.activePiece!.pivot];
    game.move([0, -1, 0]);
    expect(game.activePiece!.pivot).toEqual([start[0], start[1] - 1, start[2]]);
  });
});

describe('Cube: a whole game', () => {
  it('plays to the end with every glass taking turns', () => {
    const game = new CubeGame({ seed: 9, ramp: { everyPoints: 500, factor: 0.9, minActive: 0.3, minInactive: 0.8 } });
    for (let i = 0; i < 3000 && !game.isGameOver; i++) {
      game.control([0, BACK, FRONT][i % 3]);
      game.dropActive();
      run(game, 0.5);
    }
    expect(game.isGameOver).toBe(true);
    expect(game.placed).toBeGreaterThan(5);
  });

  it('steps fast while soft drop is held', () => {
    const game = new CubeGame({ seed: 2, inactiveFalls: false });
    const start = game.activePiece!.pivot[1];
    game.softDrop = true;
    run(game, 0.3);
    expect(start - game.activePiece!.pivot[1]).toBeGreaterThan(3);
  });
});

describe('Cube: sizes and the next sticks', () => {
  it('gives each glass its own next stick', () => {
    const game = new CubeGame({ seed: 12, inactiveFalls: false });
    const top = game.active;
    const coming = game.nextOf(top);
    const others = SIDES.filter((s) => s.id !== top).map((s) => game.nextOf(s.id));
    game.dropActive();
    run(game, 1);
    expect(game.activePiece!.colors).toEqual(coming);
    expect(SIDES.filter((s) => s.id !== top).map((s) => game.nextOf(s.id))).toEqual(others);
  });

  it('plays an even cube: the sticks across the screen fall in the nearer middle layer, before a tip and after', () => {
    const game = new CubeGame({ seed: 13, centre: 10, arm: 9, inactiveFalls: false });
    expect(game.half).toBe(4.5);
    expect(game.layer).toBe(0.5);
    for (const piece of game.pieces.values()) if (game.inPlane(piece.side)) expect(game.depthOf(piece.pivot)).toBe(0.5);
    // Three seen in a row at the bottom, at whole and half depths alike.
    const h = game.half;
    for (const sx of [-1.5, -0.5, 0.5]) game.hub.set(game.cellAt(sx, -h, sx + 1), 1);
    expect(game.findMatches().runs).toHaveLength(1);
    const TOP = sideOf(1, 1);
    const tipped = { down: BACK, plane: [0, 1, 0] as Vec, frame: { right: [1, 0, 0] as Vec, up: [0, 0, -1] as Vec } };
    const upright = { down: TOP, plane: [0, 0, 1] as Vec, frame: { right: [1, 0, 0] as Vec, up: [0, 1, 0] as Vec } };
    for (let i = 0; i < 3000 && !game.isGameOver; i++) {
      if (i % 7 === 3) {
        const to = i % 2 ? tipped : upright;
        game.turn(to.down, to.plane, to.frame, true);
        run(game, 2);
        for (const piece of game.pieces.values()) {
          if (game.inPlane(piece.side)) expect(game.depthOf(piece.pivot), `glass ${piece.side}`).toBe(0.5);
        }
      }
      game.dropActive();
      run(game, 0.5);
    }
    expect(game.isGameOver).toBe(true);
    expect(game.placed).toBeGreaterThan(5);
  });
});

describe('Cube: the tutorial', () => {
  const settle = (game: CubeGame) => {
    for (let i = 0; i < 400 && game.phase !== 'playing'; i++) game.update(0.02);
  };

  it('holds the sticks still in the lessons, and lets them fall in free play', () => {
    const held = lessonGame(1);
    const start = [...held.activePiece!.pivot];
    run(held, 3);
    expect(held.activePiece!.pivot).toEqual(start);
    const free = lessonGame(CUBE_LESSON_LAST);
    const top = free.activePiece!.pivot[1];
    run(free, 3);
    expect(free.activePiece!.pivot[1]).toBeLessThan(top);
  });

  it('pops a line with the stick on top dropped where it is', () => {
    const game = lessonGame(1);
    expect(game.findMatches().runs).toHaveLength(0);
    game.dropActive();
    run(game, 0.3);
    expect(game.matches).toBe(1);
  });

  it('pops a line with the stick in front dropped to the back of the cube', () => {
    const game = lessonGame(2);
    game.control(FRONT);
    expect(game.landing()).toMatchObject({ count: 3 });
    game.dropActive();
    run(game, 0.3);
    expect(game.matches).toBe(1);
  });

  it('pops the tops of the columns when tipped back over the top', () => {
    const game = lessonGame(3);
    expect(game.findMatches().runs).toHaveLength(0);
    expect(game.previewTurn([0, 1, 0], { right: [1, 0, 0], up: [0, 0, -1] }).popped).toBe(3);
    game.turn(BACK, [0, 1, 0], { right: [1, 0, 0], up: [0, 0, -1] }, true);
    settle(game);
    run(game, 1);
    expect(game.matches).toBe(1);
  });

  it('starts every lesson with nothing to pop', () => {
    for (let lesson = 0; lesson <= CUBE_LESSON_LAST; lesson++) {
      const game = lessonGame(lesson);
      expect(game.findMatches().runs, `lesson ${lesson}`).toHaveLength(0);
      expect(game.settle(), `lesson ${lesson}`).toHaveLength(0);
    }
  });
});
