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
  glassOpposite('Стакан напротив', 'Развернуть поле на 180°', ActionGroup.glass),
  pause('Пауза', 'Пауза и меню', ActionGroup.game),
  restart('Заново', 'Начать партию сначала', ActionGroup.game);

  const GameAction(this.label, this.hint, this.group);

  /// Short name, shown in the settings and under the button.
  final String label;
  final String hint;
  final ActionGroup group;

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

/// Where an action is listed in the settings.
enum ActionGroup {
  piece('Фигура'),
  glass('Стаканы'),
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
  PadSlot.up: GameAction.hardDrop,
  PadSlot.left: GameAction.moveLeft,
  PadSlot.right: GameAction.moveRight,
  PadSlot.down: GameAction.softDrop,
  PadSlot.center: GameAction.none,
};

/// The right pad turns things: the piece up and down, the cross sideways.
const PadLayout defaultRightPad = {
  PadSlot.up: GameAction.rotateCW,
  PadSlot.left: GameAction.glassLeft,
  PadSlot.right: GameAction.glassRight,
  PadSlot.down: GameAction.rotateCCW,
  PadSlot.center: GameAction.glassOpposite,
};
