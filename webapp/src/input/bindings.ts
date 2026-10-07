/** Everything the keyboard can do in the game. */
export type Action =
  | 'moveLeft'
  | 'moveRight'
  | 'rotateCW'
  | 'rotateCCW'
  | 'softDrop'
  | 'hardDrop'
  | 'glassLeft'
  | 'glassRight'
  | 'glassOpposite'
  | 'pause'
  | 'restart';

export type ActionGroup = 'piece' | 'glass' | 'game';

export interface ActionInfo {
  id: Action;
  label: string;
  hint: string;
  group: ActionGroup;
}

export const ACTIONS: readonly ActionInfo[] = [
  { id: 'moveLeft', label: 'Влево', hint: 'Сдвинуть фигуру влево', group: 'piece' },
  { id: 'moveRight', label: 'Вправо', hint: 'Сдвинуть фигуру вправо', group: 'piece' },
  { id: 'rotateCW', label: 'Поворот по часовой', hint: 'Повернуть фигуру на четверть оборота', group: 'piece' },
  { id: 'rotateCCW', label: 'Поворот против часовой', hint: 'Повернуть в обратную сторону', group: 'piece' },
  { id: 'softDrop', label: 'Мягкий сброс', hint: 'Пока держите — фигура падает быстро', group: 'piece' },
  { id: 'hardDrop', label: 'Сброс', hint: 'Мгновенно поставить фигуру', group: 'piece' },
  { id: 'glassLeft', label: 'Стакан слева', hint: 'Поднять наверх стакан, который слева', group: 'glass' },
  { id: 'glassRight', label: 'Стакан справа', hint: 'Поднять наверх стакан, который справа', group: 'glass' },
  { id: 'glassOpposite', label: 'Стакан напротив', hint: 'Развернуть поле на 180°', group: 'glass' },
  { id: 'pause', label: 'Пауза', hint: 'Пауза и меню', group: 'game' },
  { id: 'restart', label: 'Заново', hint: 'Начать партию сначала', group: 'game' },
];

export const GROUP_TITLES: Record<ActionGroup, string> = {
  piece: 'Фигура',
  glass: 'Стаканы',
  game: 'Игра',
};

/** Keys per action, as `KeyboardEvent.code` values — the physical key, so a
 * binding works the same in any keyboard layout. Two slots per action. */
export type Bindings = Record<Action, string[]>;

export const SLOTS_PER_ACTION = 2;

export const defaultBindings: Bindings = {
  moveLeft: ['ArrowLeft'],
  moveRight: ['ArrowRight'],
  rotateCW: ['ArrowUp', 'KeyX'],
  rotateCCW: ['KeyZ'],
  softDrop: ['ArrowDown'],
  hardDrop: ['Space'],
  glassLeft: ['KeyA'],
  glassRight: ['KeyD'],
  glassOpposite: ['KeyS'],
  pause: ['Escape', 'KeyP'],
  restart: ['KeyR'],
};

export const cloneBindings = (bindings: Bindings): Bindings =>
  Object.fromEntries(ACTIONS.map(({ id }) => [id, [...bindings[id]]])) as Bindings;

/** The action a key triggers, if any. */
export function actionForCode(bindings: Bindings, code: string): Action | null {
  for (const { id } of ACTIONS) if (bindings[id].includes(code)) return id;
  return null;
}

/** Puts `code` into slot `slot` of `action`. A key can only do one thing:
 * it is removed from wherever else it was bound. Returns new bindings. */
export function bindKey(bindings: Bindings, action: Action, slot: number, code: string): Bindings {
  const next = cloneBindings(bindings);
  for (const { id } of ACTIONS) next[id] = next[id].filter((bound) => bound !== code);
  const keys = next[action];
  if (slot < keys.length) keys[slot] = code;
  else keys.push(code);
  next[action] = keys.slice(0, SLOTS_PER_ACTION);
  return next;
}

/** Empties slot `slot` of `action`. Returns new bindings. */
export function unbindKey(bindings: Bindings, action: Action, slot: number): Bindings {
  const next = cloneBindings(bindings);
  next[action] = next[action].filter((_, i) => i !== slot);
  return next;
}

/** Makes sense of whatever was stored: unknown actions are dropped, missing
 * ones get their defaults, a key bound twice keeps its first use. */
export function sanitizeBindings(raw: unknown): Bindings {
  const result = cloneBindings(defaultBindings);
  if (typeof raw !== 'object' || raw === null) return result;
  const seen = new Set<string>();
  for (const { id } of ACTIONS) {
    const stored = (raw as Record<string, unknown>)[id];
    if (!Array.isArray(stored)) continue;
    result[id] = stored
      .filter((code): code is string => typeof code === 'string' && code.length > 0)
      .slice(0, SLOTS_PER_ACTION);
  }
  for (const { id } of ACTIONS) {
    result[id] = result[id].filter((code) => {
      if (seen.has(code)) return false;
      seen.add(code);
      return true;
    });
  }
  return result;
}

const SPECIAL_LABELS: Record<string, string> = {
  ArrowLeft: '←',
  ArrowRight: '→',
  ArrowUp: '↑',
  ArrowDown: '↓',
  Space: 'Пробел',
  Escape: 'Esc',
  Enter: 'Enter',
  NumpadEnter: 'Num Enter',
  Tab: 'Tab',
  Backspace: 'Backspace',
  ShiftLeft: 'Shift ←',
  ShiftRight: 'Shift →',
  ControlLeft: 'Ctrl ←',
  ControlRight: 'Ctrl →',
  AltLeft: 'Alt ←',
  AltRight: 'Alt →',
  Comma: ',',
  Period: '.',
  Slash: '/',
  Semicolon: ';',
  Quote: "'",
  BracketLeft: '[',
  BracketRight: ']',
  Backslash: '\\',
  Minus: '-',
  Equal: '=',
  Backquote: '`',
};

/** A short name for a key, for showing on a keycap. */
export function keyLabel(code: string): string {
  if (code in SPECIAL_LABELS) return SPECIAL_LABELS[code];
  if (code.startsWith('Key')) return code.slice(3);
  if (code.startsWith('Digit')) return code.slice(5);
  if (code.startsWith('Numpad')) return `Num ${code.slice(6)}`;
  return code;
}
