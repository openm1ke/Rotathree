/// What a store screenshot says over its shot: a small coloured kicker, a
/// big title and a line under it.
class Caption {
  const Caption(this.kicker, this.title, this.line);

  final String kicker, title, line;
}

/// The store screenshots in their order, each a raw shot and its words: the
/// game of glasses first, Cube among them, then the settings and the
/// achievements.
const shots = <String, Map<String, Caption>>{
  'cross': {
    'ru': Caption('Головоломка', 'Поверни стакан', 'Четыре стакана вокруг одного центра'),
    'en': Caption('Puzzle', 'Turn the glass', 'Four glasses around one centre'),
  },
  'combo': {
    'ru': Caption('Каскады', 'Собери три', 'Линии лопаются — всё сверху осыпается'),
    'en': Caption('Cascades', 'Match three', 'Lines pop, everything above falls'),
  },
  'nightmare': {
    'ru': Caption('Испытание', 'Кошмар', 'Шесть цветов, и скорость растёт'),
    'en': Caption('Challenge', 'Nightmare', 'Six colours and rising speed'),
  },
  'campaign': {
    'ru': Caption('Кампания', '24 уровня', '16 уровней со стаканами и 8 — в кубе'),
    'en': Caption('Campaign', '24 levels', '16 levels of glasses and 8 inside the cube'),
  },
  'cube-volume': {
    'ru': Caption('Новый режим', 'Куб · 3D', 'Шесть стаканов вокруг куба'),
    'en': Caption('New mode', 'Cube · 3D', 'Six glasses around a cube'),
  },
  'cube-lean': {
    'ru': Caption('Куб', 'Опрокинь куб', 'Глубина станет новой картинкой'),
    'en': Caption('Cube', 'Tip the cube', 'Its depth becomes the new picture'),
  },
  'settings-controls': {
    'ru': Caption('Настройки', 'Настрой под себя', 'Кнопки, цвета, эффекты и звук'),
    'en': Caption('Settings', 'Make it yours', 'Buttons, colours, effects and sound'),
  },
  'achievements': {
    'ru': Caption('Новое', '25 достижений', 'Засчитывается и то, что сыграно раньше'),
    'en': Caption('New', '25 achievements', 'What you played before counts too'),
  },
};
