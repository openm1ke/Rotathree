/// Everything a key or a pad button can ask of the game.
enum GameAction {
  none('—', 'Ничего', ActionGroup.piece),
  moveLeft('Влево', 'Сдвинуть фигуру влево', ActionGroup.piece),
  moveRight('Вправо', 'Сдвинуть фигуру вправо', ActionGroup.piece),
  rotateCW('Поворот по часовой', 'Повернуть фигуру на четверть оборота', ActionGroup.piece),
  rotateCCW('Поворот против часовой', 'Повернуть в обратную сторону', ActionGroup.piece),
  softDrop('Мягкий сброс', 'Пока держите — фигура падает быстро', ActionGroup.piece),
  hardDrop('Сброс', 'Мгновенно поставить фигуру', ActionGroup.piece),
  glassLeft('Стакан слева', 'Поднять наверх стакан, который слева', ActionGroup.glass),
  glassRight('Стакан справа', 'Поднять наверх стакан, который справа', ActionGroup.glass),
  glassOpposite('Стакан напротив', 'Развернуть поле на 180°', ActionGroup.glass, ActionScope.flat),
  pause('Пауза', 'Пауза и меню', ActionGroup.game),
  restart('Заново', 'Начать партию сначала', ActionGroup.game),
  // Cube's own come last: a key a player gave to a shared action stays there.
  tipBack(
    'Опрокинуть: задний наверх',
    'Держите — посмотреть, как ляжет куб с задним стаканом наверху; отпустите — опрокинуть',
    ActionGroup.cube,
    ActionScope.cube,
  ),
  tipFront(
    'Опрокинуть: передний наверх',
    'Держите — посмотреть, как ляжет куб с передним стаканом наверху; отпустите — опрокинуть',
    ActionGroup.cube,
    ActionScope.cube,
  ),
  frontGlass('Передний стакан', 'Вести его фигуру; ещё раз — назад к верхнему', ActionGroup.cube, ActionScope.cube),
  backGlass('Задний стакан', 'Вести его фигуру; ещё раз — назад к верхнему', ActionGroup.cube, ActionScope.cube),
  depthGlass('Стакан глубины', 'По кругу: верхний, передний, задний', ActionGroup.cube, ActionScope.cube),
  peek('Объём', 'Держите — увидеть куб в объёме', ActionGroup.cube, ActionScope.cube);

  const GameAction(this.label, this.hint, this.group, [this.scope]);

  /// Short name, shown in the settings and under the button.
  final String label;
  final String hint;
  final ActionGroup group;

  /// Which game the action belongs to; null: both. A key may do one thing in
  /// the flat game and another in Cube.
  final ActionScope? scope;

  /// Whether the action is on in [game].
  bool inScope(ActionScope game) => scope == null || scope == game;

  /// Actions that work for as long as the key or button is held; the rest
  /// fire once per press.
  bool get isHeld => this == moveLeft || this == moveRight || this == softDrop;

  /// The action called [name], or null.
  static GameAction? byName(Object? name) {
    for (final action in values) {
      if (action.name == name) return action;
    }
    return null;
  }
}

/// Which game an action belongs to: the flat cross or Cube.
enum ActionScope { flat, cube }

/// Where an action is listed in the settings.
enum ActionGroup {
  piece('Фигура'),
  glass('Стаканы'),
  cube('Куб'),
  game('Игра');

  const ActionGroup(this.title);

  final String title;
}

/// The buttons of one pad.
enum PadSlot {
  up('Вверх'),
  left('Влево'),
  right('Вправо'),
  down('Вниз'),
  center('Центр');

  const PadSlot(this.label);

  final String label;
}

/// What each button of one pad does.
typedef PadLayout = Map<PadSlot, GameAction>;

/// The left pad steers the piece, the way a D-pad does in any falling-block
/// game.
const PadLayout defaultLeftPad = {
  PadSlot.up: GameAction.rotateCW,
  PadSlot.left: GameAction.moveLeft,
  PadSlot.right: GameAction.moveRight,
  PadSlot.down: GameAction.hardDrop,
  PadSlot.center: GameAction.none,
};

/// Cube's pads as they come: the left one plays the stick, its centre picks
/// the glass in front or behind; the right one tips the hub (up, down — or
/// moves the stick in front or behind up and down), turns the cross (left,
/// right) and, held in the centre, opens the volume. Where the pads are and
/// how they look is shared with the flat game's.
const PadLayout defaultCubeLeftPad = {
  PadSlot.up: GameAction.rotateCW,
  PadSlot.left: GameAction.moveLeft,
  PadSlot.right: GameAction.moveRight,
  PadSlot.down: GameAction.hardDrop,
  PadSlot.center: GameAction.depthGlass,
};

const PadLayout defaultCubeRightPad = {
  PadSlot.up: GameAction.tipBack,
  PadSlot.left: GameAction.glassLeft,
  PadSlot.right: GameAction.glassRight,
  PadSlot.down: GameAction.tipFront,
  PadSlot.center: GameAction.peek,
};

/// The right pad turns things: the piece up and down, the cross sideways.
const PadLayout defaultRightPad = {
  PadSlot.up: GameAction.rotateCW,
  PadSlot.left: GameAction.glassLeft,
  PadSlot.right: GameAction.glassRight,
  PadSlot.down: GameAction.rotateCCW,
  PadSlot.center: GameAction.glassOpposite,
};
