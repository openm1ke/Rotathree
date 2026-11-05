// The flat game's tutorial: its lessons, as the panel above the glass shows
// them.

/** One short line per lesson, read at a glance above the glass; the keys or
 * the glowing pad buttons say the rest. A lesson with an action goes on by
 * itself once the action is done; the first and the last wait for a button. */
export const TUTORIAL_LESSONS = [
  ['Собирай 3 в ряд', 'Три клетки одного цвета исчезают'],
  ['Двигай фигуру', ''],
  ['Поверни фигуру', ''],
  ['Брось — собери 3', ''],
  ['Поверни стакан', 'Наверху — активный стакан'],
  ['Следи за всеми стаканами', 'Активный падает быстрее — переключайся'],
] as const;
