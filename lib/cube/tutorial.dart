// Cube's tutorial (webapp/src/cube/tutorial.ts): a few short lessons, each
// on a board laid out for it, so that the one thing it teaches happens at
// the first try. The sticks hold still in them, and move only when the
// player moves them.
import '../ui/input/game_action.dart';
import 'rules.dart';

/// Title and one line of each lesson, read at a glance above the field. The
/// first and the last wait for a button; the others go on once done.
const cubeLessons = <(String, String)>[
  ('Это куб', 'Шесть стаканов вокруг него. Крест на экране — вид спереди'),
  ('Линия — из того, что видно', 'Блоки лежат на разной глубине, а считается картинка. Брось фигуру'),
  ('Поверни крест', '← по часовой, → против часовой, как в 2D. Весь куб поворачивается вместе с ним'),
  ('Поверни скрытые стаканы', '↑ — наверх задний стакан, ↓ — передний. Держи — покажет, что лопнет. Отпусти — повернёт'),
  ('Загляни в объём', 'Держи — куб раскроется в 3D'),
  ('Теперь сам', 'Собирай линии. На паузе куб можно осмотреть со всех сторон'),
];

final cubeLessonLast = cubeLessons.length - 1;

/// What each lesson asks for: any of its actions. Their pad buttons glow.
const cubeLessonActions = <int, List<GameAction>>{
  1: [GameAction.hardDrop],
  2: [GameAction.glassLeft, GameAction.glassRight],
  3: [GameAction.tipBack, GameAction.tipFront],
  4: [GameAction.peek],
};

/// The first thing the lesson asks for that no pad button does, if any: the
/// lesson then offers to do it for the player.
GameAction? missingOnPads(int lesson, PadLayout left, PadLayout right) {
  final actions = cubeLessonActions[lesson] ?? const [];
  if (actions.isEmpty) return null;
  final assigned = {...left.values, ...right.values};
  return actions.any(assigned.contains) ? null : actions.first;
}

/// The glass at the top of the screen, as a new game lies.
final _top = sides.indexWhere((s) => s.axis == 1 && s.sign == 1);

// The colours the boards are painted in: the first four of the set.
const _red = 0, _blue = 1, _yellow = 2, _green = 3;

/// Paints blocks given as (across, up, depth, colour) on the screen of a new
/// game: across and up from the middle of the cross, depth towards the eye.
void _paint(CubeGame game, List<(double, double, double, int)> blocks) {
  for (final (sx, sy, d, color) in blocks) {
    game.hub.set(game.cellAt(sx, sy, d), color);
  }
}

/// Blocks scattered through the depth, which only the volume shows.
void _depthBoard(CubeGame game) {
  final h = game.half;
  final blocks = <(double, double, double, int)>[];
  for (var i = -h; i <= h; i++) {
    blocks.add((i, -h, i, (i + h).round() % 4));
    if (i.round() % 2 == 0) blocks.add((i, -h + 1, -i, (i + h + 2).round() % 4));
  }
  _paint(game, blocks);
}

/// A new game laid out for the lesson.
CubeGame lessonGame(int lesson) {
  final last = lesson >= cubeLessonLast;
  final game = CubeGame(CubeConfig(seed: 20 + lesson, numberOfColors: 4, inactiveFalls: last))..stepsHeld = !last;
  final h = game.half;
  final top = game.pieces[_top]!;
  switch (lesson) {
    case 0:
    case 4:
      _depthBoard(game);
    case 1:
      // Yellow at depths 2 and −3, and a yellow stick over the gap beside
      // them: seen in a row, the three pop. Red hides behind the first one.
      _paint(game, [
        (-3, -h, 1, _blue),
        (-2, -h, -2, _red),
        (-1, -h, 2, _yellow),
        (-1, -h, -1, _red),
        (0, -h, -3, _yellow),
      ]);
      game.pieces[_top] = Stick(
        side: top.side,
        colors: const [_yellow, _green, _blue],
        pivot: game.cellAt(2, h + 3, 0),
        dir: const Vec(1, 0, 0),
      );
    case 2:
      // A few blocks at the bottom: they go round with the cross.
      _paint(game, [
        (-1, -h, 0, _green),
        (0, -h, 0, _yellow),
        (1, -h, 0, _red),
        (0, -h + 1, 0, _blue),
      ]);
    case 3:
      // Three columns whose tops are yellow: from above, the tops make a line.
      _paint(game, [
        (-1, -h, 0, _blue),
        (-1, -h + 1, 0, _red),
        (-1, -h + 2, 0, _yellow),
        (0, -h, 0, _red),
        (0, -h + 1, 0, _yellow),
        (1, -h, 0, _green),
        (1, -h + 1, 0, _blue),
        (1, -h + 2, 0, _yellow),
      ]);
  }
  return game;
}
