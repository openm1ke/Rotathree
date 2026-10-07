/// Everything a button of the on-screen pads can do.
enum PadAction {
  none('—', 'Ничего'),
  moveLeft('Влево', 'Сдвинуть фигуру влево'),
  moveRight('Вправо', 'Сдвинуть фигуру вправо'),
  rotateCW('Поворот ↻', 'Повернуть фигуру по часовой'),
  rotateCCW('Поворот ↺', 'Повернуть фигуру против часовой'),
  softDrop('Быстрее', 'Пока держите — фигура падает быстро'),
  hardDrop('Сброс', 'Мгновенно поставить фигуру'),
  glassLeft('Стакан слева', 'Поднять наверх стакан, который слева'),
  glassRight('Стакан справа', 'Поднять наверх стакан, который справа'),
  glassOpposite('Стакан напротив', 'Развернуть поле на 180°'),
  pause('Пауза', 'Пауза и меню');

  const PadAction(this.label, this.hint);

  /// Short name, shown in the settings and under the button.
  final String label;
  final String hint;

  /// Actions that work for as long as the button is held; the rest fire once
  /// per press.
  bool get isHeld =>
      this == moveLeft || this == moveRight || this == softDrop;

  static PadAction byName(Object? name, PadAction fallback) {
    for (final action in values) {
      if (action.name == name) return action;
    }
    return fallback;
  }
}

/// The five buttons of one pad.
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
typedef PadLayout = Map<PadSlot, PadAction>;

/// The left pad steers the piece, the way a D-pad does in any falling-block
/// game.
const PadLayout defaultLeftPad = {
  PadSlot.up: PadAction.hardDrop,
  PadSlot.left: PadAction.moveLeft,
  PadSlot.right: PadAction.moveRight,
  PadSlot.down: PadAction.softDrop,
  PadSlot.center: PadAction.none,
};

/// The right pad turns things: the piece up and down, the cross sideways.
const PadLayout defaultRightPad = {
  PadSlot.up: PadAction.rotateCW,
  PadSlot.left: PadAction.glassLeft,
  PadSlot.right: PadAction.glassRight,
  PadSlot.down: PadAction.rotateCCW,
  PadSlot.center: PadAction.glassOpposite,
};
