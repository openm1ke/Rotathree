# Rotathree — веб-версия

Та же игра, что и во Flutter-проекте уровнем выше, для браузера и клавиатуры.

Играть: https://openm1ke.github.io/Rotathree/ — страница собирается из этой
папки и публикуется через GitHub Actions (`.github/workflows/pages.yml`) при
каждом пуше в `main`, который её затрагивает.

Стек такой же, как у веб-порта RuneChess: **Vite + TypeScript + React**, тесты —
**Vitest**. Игровой движок в `src/game` — чистый TypeScript без React и DOM,
построчный порт `lib/game` из Flutter-проекта.

## Запуск

```bash
npm install
```

```bash
npm run dev
```

Откроется на `http://localhost:5183`.

## Проверки

```bash
npm run check
```

Это `typecheck` + `lint` + `test` + `build` подряд.

## Управление

Клавиши по умолчанию (меняются в «Настройки → Управление», привязка идёт к
физической клавише, поэтому раскладка не важна):

| Действие | Клавиши |
|---|---|
| Сдвиг фигуры | ← → |
| Поворот по часовой / против | ↑ или X / Z |
| Мягкий сброс (держать) | ↓ |
| Сброс | Пробел |
| Стакан слева / справа / напротив | A / D / S |
| Пауза | Esc или P |
| Заново | R |

Удержание ← → повторяет сдвиг: задержка (DAS) и интервал (ARR) настраиваются.
Клик по рукаву мышью тоже поднимает этот стакан наверх.

## Структура

```
src/
  game/        движок: config, board, glass, piece, placement, matchDetector,
               gravity, cascade, generator, incoming, engine
  render/      canvas: renderer (поле, блоки), effects (толчки, частицы), theme
  input/       bindings (привязки клавиш), keyboard (автоповтор DAS/ARR)
  services/    settingsStore (localStorage)
  components/  MenuScreen, GameScreen, Hud, SettingsPanel
  styles/      tokens.css, global.css
  tests/       model, engine, input
```

Настройки (клавиши, автоповтор, скорость, длина рукава, число цветов) хранятся в
`localStorage` под ключом `rotathree.settings.v1`.
