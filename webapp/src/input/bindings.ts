import { USES_ESCAPE } from '../platform/target';

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
  | 'tipBack'
  | 'tipFront'
  | 'frontGlass'
  | 'backGlass'
  | 'depthGlass'
  | 'peek'
  | 'pause'
  | 'restart';

export type ActionGroup = 'piece' | 'glass' | 'cube' | 'game';

/** Which game an action belongs to: the flat cross, Cube, or both. A key may
 * do one thing in the flat game and another in Cube. */
export type ActionScope = 'flat' | 'cube';

export interface ActionInfo {
  id: Action;
  label: string;
  hint: string;
  group: ActionGroup;
  /** Absent: the action is the same in both games. */
  scope?: ActionScope;
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
  { id: 'glassOpposite', label: 'Стакан напротив', hint: 'Развернуть поле на 180°', group: 'glass', scope: 'flat' },
  { id: 'pause', label: 'Пауза', hint: 'Пауза и меню', group: 'game' },
  { id: 'restart', label: 'Заново', hint: 'Начать партию сначала', group: 'game' },
  // Cube's own come last: a key a player gave to a shared action stays there.
  { id: 'tipBack', label: 'Опрокинуть: задний наверх', hint: 'Держите — посмотреть, как ляжет куб с задним стаканом наверху; отпустите — опрокинуть', group: 'cube', scope: 'cube' },
  { id: 'tipFront', label: 'Опрокинуть: передний наверх', hint: 'Держите — посмотреть, как ляжет куб с передним стаканом наверху; отпустите — опрокинуть', group: 'cube', scope: 'cube' },
  { id: 'frontGlass', label: 'Передний стакан', hint: 'Вести его фигуру; ещё раз — назад к верхнему', group: 'cube', scope: 'cube' },
  { id: 'backGlass', label: 'Задний стакан', hint: 'Вести его фигуру; ещё раз — назад к верхнему', group: 'cube', scope: 'cube' },
  { id: 'depthGlass', label: 'Стакан глубины', hint: 'По кругу: верхний, передний, задний', group: 'cube', scope: 'cube' },
  { id: 'peek', label: 'Объём', hint: 'Держите — увидеть куб в объёме', group: 'cube', scope: 'cube' },
];

export const GROUP_TITLES: Record<ActionGroup, string> = {
  piece: 'Фигура',
  glass: 'Стаканы',
  cube: 'Куб',
  game: 'Игра',
};

/** Whether two actions can be on at the same time, so may not share a key. */
const overlaps = (a: ActionInfo, b: ActionInfo): boolean => !a.scope || !b.scope || a.scope === b.scope;
const infoOf = (action: Action): ActionInfo => ACTIONS.find(({ id }) => id === action)!;

/** Keys per action, as `KeyboardEvent.code` values — the physical key, so a
 * binding works the same in any keyboard layout. Two slots per action. */
export type Bindings = Record<Action, string[]>;

export const SLOTS_PER_ACTION = 2;

export const defaultBindings: Bindings = {
  moveLeft: ['KeyA'],
  moveRight: ['KeyD'],
  rotateCW: ['KeyW'],
  rotateCCW: [],
  softDrop: ['KeyX'],
  hardDrop: ['KeyS', 'Space'],
  // Q and E turn the cross too, beside A, W, S, D: the game plays with one hand.
  glassLeft: ['ArrowLeft', 'KeyQ'],
  glassRight: ['ArrowRight', 'KeyE'],
  glassOpposite: ['ArrowUp', 'ArrowDown'],
  // Cube's own: the arrows up and down tip the hub there instead.
  tipBack: ['ArrowUp'],
  tipFront: ['ArrowDown'],
  frontGlass: ['KeyZ'],
  backGlass: ['KeyC'],
  depthGlass: [],
  peek: ['KeyV'],
  pause: USES_ESCAPE ? ['Escape', 'KeyP'] : ['KeyP'],
  restart: ['KeyN'],
};

export const cloneBindings = (bindings: Bindings): Bindings =>
  Object.fromEntries(ACTIONS.map(({ id }) => [id, [...bindings[id]]])) as Bindings;

/** The action a key triggers in the given game, if any. */
export function actionForCode(bindings: Bindings, code: string, scope: ActionScope = 'flat'): Action | null {
  for (const { id, scope: own } of ACTIONS) if ((!own || own === scope) && bindings[id].includes(code)) return id;
  return null;
}

/** Whether the game may bind `code`: not Esc where the platform keeps it. */
const usable = (code: string) => USES_ESCAPE || code !== 'Escape';

/** Puts `code` into slot `slot` of `action`. A key can only do one thing:
 * it is removed from wherever else it was bound. Returns new bindings. */
export function bindKey(bindings: Bindings, action: Action, slot: number, code: string): Bindings {
  const next = cloneBindings(bindings);
  if (!usable(code)) return next;
  const info = infoOf(action);
  // Only from actions that can be on at the same time: a key may tip the
  // hub in Cube and turn the cross round in the flat game.
  for (const other of ACTIONS) if (overlaps(info, other)) next[other.id] = next[other.id].filter((bound) => bound !== code);
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

/** Keys that joined the defaults later: a save that still has the action's
 * earlier default gets them too, unless it uses the key for something else. */
const LATER_DEFAULTS: readonly { action: Action; was: readonly string[]; key: string }[] = [
  { action: 'glassLeft', was: ['ArrowLeft'], key: 'KeyQ' },
  { action: 'glassRight', was: ['ArrowRight'], key: 'KeyE' },
  { action: 'softDrop', was: [], key: 'KeyX' },
];

/** Makes sense of whatever was stored: unknown actions are dropped, missing
 * ones get their defaults, a key bound twice keeps its first use. */
export function sanitizeBindings(raw: unknown): Bindings {
  const result = cloneBindings(defaultBindings);
  if (typeof raw !== 'object' || raw === null) return result;
  for (const { id } of ACTIONS) {
    const stored = (raw as Record<string, unknown>)[id];
    if (!Array.isArray(stored)) continue;
    result[id] = stored
      .filter((code): code is string => typeof code === 'string' && code.length > 0 && usable(code))
      .slice(0, SLOTS_PER_ACTION);
  }
  // A key keeps its first use among the actions that can be on together.
  const kept: { info: ActionInfo; code: string }[] = [];
  for (const info of ACTIONS) {
    result[info.id] = result[info.id].filter((code) => {
      if (kept.some((k) => k.code === code && overlaps(k.info, info))) return false;
      kept.push({ info, code });
      return true;
    });
  }
  const seen = new Set(kept.map((k) => k.code));
  for (const { action, was, key } of LATER_DEFAULTS) {
    const keys = result[action];
    const unchanged = keys.length === was.length && keys.every((code, i) => code === was[i]);
    if (unchanged && !seen.has(key) && keys.length < SLOTS_PER_ACTION) {
      result[action] = [...keys, key];
      seen.add(key);
    }
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
