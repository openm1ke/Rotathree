// Cube's tutorial: a few short lessons, each on a board laid out for it, so
// that the one thing it teaches happens at the first try. The sticks hold
// still in them, and move only when the player moves them.
import type { Action } from '../input/bindings';
import { CubeGame, SIDES, type Vec } from './rules';

/** Title and one line of each lesson, read at a glance above the field. The
 * first and the last wait for a button; the others go on once done. */
export const CUBE_LESSONS = [
  ['Это куб', 'Шесть стаканов вокруг него. Крест на экране — вид спереди'],
  ['Линия — из того, что видно', 'Блоки лежат на разной глубине, а считается картинка. Брось фигуру'],
  ['Стакан спереди', 'Возьми его и брось: фигура летит вглубь. Метка в углу — будет ли её видно'],
  ['Опрокинь куб', 'Держи — покажет, как ляжет и что лопнет. Отпусти — опрокинет'],
  ['Загляни в объём', 'Держи — куб раскроется в 3D'],
  ['Теперь сам', 'Крест поворачивается, как в 2D. ↑ ↓ — опрокинуть куб'],
] as const;

export const CUBE_LESSON_LAST = CUBE_LESSONS.length - 1;

/** What a lesson asks for: the keys shown, and the pad buttons that glow
 * (the pads pick the glass in front by cycling the glasses in depth). */
export const LESSON_KEYS: Record<number, readonly Action[]> = {
  1: ['hardDrop'],
  2: ['frontGlass', 'hardDrop'],
  3: ['tipBack'],
  4: ['peek'],
};
export const LESSON_PADS: Record<number, readonly Action[]> = {
  1: ['hardDrop'],
  2: ['depthGlass', 'hardDrop'],
  3: ['tipBack'],
  4: ['peek'],
};

/** The glass at the top of the screen and the one in front, as a new game
 * lies. */
const TOP = SIDES.findIndex((s) => s.axis === 1 && s.sign === 1);
const FRONT = SIDES.findIndex((s) => s.axis === 2 && s.sign === 1);

// The colours the boards are painted in: the first four of the set.
const RED = 0;
const BLUE = 1;
const YELLOW = 2;
const GREEN = 3;

/** Paints blocks given as [across, up, depth, colour] on the screen of a new
 * game: across and up from the middle of the cross, depth towards the eye. */
function paint(game: CubeGame, blocks: readonly (readonly [number, number, number, number])[]): void {
  for (const [sx, sy, d, color] of blocks) game.hub.set(game.cellAt(sx, sy, d), color);
}

/** Blocks scattered through the depth, which only the volume shows. */
function depthBoard(game: CubeGame): void {
  const h = game.half;
  const blocks: [number, number, number, number][] = [];
  for (let i = -h; i <= h; i++) {
    blocks.push([i, -h, i, (i + h) % 4]);
    if (i % 2 === 0) blocks.push([i, -h + 1, -i, (i + h + 2) % 4]);
  }
  paint(game, blocks);
}

/** A new game laid out for the lesson. */
export function lessonGame(lesson: number): CubeGame {
  const last = lesson >= CUBE_LESSON_LAST;
  const game = new CubeGame({ seed: 20 + lesson, numberOfColors: 4, inactiveFalls: last });
  game.stepsHeld = !last;
  const h = game.half;
  const top = game.pieces.get(TOP)!;
  switch (lesson) {
    case 0:
    case 4:
      depthBoard(game);
      break;
    case 1:
      // Yellow at depths 2 and −3, and a yellow stick over the gap beside
      // them: seen in a row, the three pop. Red hides behind the first one.
      paint(game, [
        [-3, -h, 1, BLUE],
        [-2, -h, -2, RED],
        [-1, -h, 2, YELLOW],
        [-1, -h, -1, RED],
        [0, -h, -3, YELLOW],
      ]);
      Object.assign(top, { pivot: game.cellAt(2, h + 3, 0), dir: [1, 0, 0] as Vec, colors: [YELLOW, GREEN, BLUE] });
      break;
    case 2: {
      // A gap between two yellows, empty all the way through: the stick in
      // front falls to the back of the cube, and is seen there.
      paint(game, [
        [-2, -h, 2, GREEN],
        [-1, -h, 1, YELLOW],
        [1, -h, -2, YELLOW],
        [2, -h, 0, RED],
      ]);
      const front = game.pieces.get(FRONT)!;
      Object.assign(front, { pivot: game.cellAt(0, -h + 1, game.middle), dir: [0, 1, 0] as Vec, colors: [YELLOW, BLUE, RED] });
      break;
    }
    case 3:
      // Three columns whose tops are yellow: from above, the tops make a line.
      paint(game, [
        [-1, -h, 0, BLUE],
        [-1, -h + 1, 0, RED],
        [-1, -h + 2, 0, YELLOW],
        [0, -h, 0, RED],
        [0, -h + 1, 0, YELLOW],
        [1, -h, 0, GREEN],
        [1, -h + 1, 0, BLUE],
        [1, -h + 2, 0, YELLOW],
      ]);
      break;
  }
  return game;
}
