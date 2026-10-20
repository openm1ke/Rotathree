# RotaThree — Playgama

Веб-версия для Playgama и её партнёрских сайтов. Требования — из чек-листа игры Playgama (`get_game_checklist` в MCP консоли разработчика, https://wiki.playgama.com/playgama/mcp/game-checklist.md).

## Сборка

```sh
cd webapp
npm run release:playgama   # сборка, проверки, zip
node tool/playgama-covers.mjs
```

- Архив: `build/releases/playgama/rotathree-playgama-<версия>.zip` и `.sha256`. В корне архива `index.html` и `playgama-bridge-config.json`.
- Обложки: `build/releases/playgama/covers/` — квадрат 800×800, вертикальная 1080×1920, горизонтальная 1920×1080. Исходник: `webapp/playgama/covers/cover.html`.
- Локальный запуск сборки: конфигурация `rotathree-playgama` (vite preview из `dist-playgama`, порт 5184). Вне Playgama Bridge отвечает из своей заглушки.

## Что делает сборка

| Пункт чек-листа | Где |
| --- | --- |
| Bridge инициализируется до всего остального; `game_ready` — через два кадра после того, как нарисовано меню | `src/main.tsx`, `src/platform/playgama.ts` |
| Английский по умолчанию и как запасной; «Авто» берёт язык платформы | `src/platform/runtime.ts`, `src/i18n/context.ts` |
| Язык можно сменить, не понимая текущего: глобус в главном меню называет другой язык на нём самом | `src/platform/LanguageSwitch.tsx` |
| Сохранения только через `bridge.storage`: все ключи читаются одним вызовом, записи одного такта уходят одним вызовом | `PlaygamaStorage` в `src/platform/playgama.ts` |
| Пауза платформы и полноэкранная реклама останавливают время, ввод и музыку, в том числе реклама, открытая ещё до старта игры (`interstitialState`); выключенный звук платформы глушит музыку | `src/platform/lifecycle.ts`, `App.tsx`, `GameScreen.tsx` |
| Межстраничная реклама в естественной паузе. Между уровнями кампании (место `level_completed`): пока табличка «Уровень N пройден» или «Новый этап» держит игру, и только когда клавиши и пальцы игрока 0,7 с ничего не нажимают и не держат; не успел отпустить — рекламы в этот раз нет. Реклама ставит игру на паузу, дальше игрок жмёт «Продолжить». После партии (место `game_over`), когда игрок нажимает «Ещё раз», «К уровням» или «В меню» на экране итогов, — не под пальцами на кнопках управления. Первые 0,7 с экран итогов ничего не нажимает и не держит фокус на кнопке: Space или Enter, зажатые с последнего броска, и палец, опущенный раньше, не выбирают за игрока (пункт 13 чек-листа) | `GameScreen.tsx` (`LEVEL_AD_STILL_MS`, `RESULT_ARM_MS`), `src/platform/hands.ts`; `armAfterMs` у `Overlay` в `ui.tsx`; не чаще раза в 60 с (`webapp/playgama/playgama-bridge-config.json`) |
| Нет внешних ссылок и ресурсов: нет страницы конфиденциальности, файлов установки, ссылок на источники музыки, на CC0 и почты автора; адреса источников музыки вырезаны из бандла | `vite.config.ts`, `LicensesTab.tsx`, проверки `tool/build-playgama.sh` |
| Нет внешней аналитики и входа. Своя телеметрия идёт только через Bridge: забеги и уровни кампании — сообщениями `level_started` / `level_paused` / `level_resumed` / `level_completed` / `level_failed` с `world` (режим) и `level` (1–16), их Bridge сам пишет в аналитику и передаёт CrazyGames, Poki и Yandex; через `analytics.send` — `level_abandoned`, шаги обучения (`tutorial_step`, `tutorial_completed`, `tutorial_skipped`, `tutorial_left`) и `performance_sample` раз в 30 с активной игры (кадры, перцентили, медленные кадры, ошибки, `build_version`) | `src/platform/telemetry.ts`, `GameScreen.tsx`; внешней аналитики и входа нет, это проверяет скрипт |
| Долгое нажатие не открывает меню браузера; у страницы нет полосы прокрутки. Главное меню вместе с «Продолжить» и карточкой кампании помещается целиком: размеры идут и от высоты, на низком горизонтальном экране список в две колонки. Где прокрутка всё же осталась, полоса тонкая, в цветах игры | `startPlaygama`; `.home` в `global.css`; проверено на 360×640, 390×844, 915×412, 1280×720 (кадр Playgama 1167×670), 2560×1440 |
| Подписи кнопок на экранных пэдах читаются: 11 px, слишком длинное слово сжимается по ширине под свою кнопку и только при нехватке места идёт 10 px | `DPad.tsx`, `.dpad__button small` в `global.css` |

Видео за награду не используется: в игре нет бонуса, который не был бы условием продолжения.

## Форма приложения (update_application_form)

- **Title:** RotaThree
- **Engine:** js
- **Category:** matching (так выбрано в консоли)
- **Devices:** DESKTOP, ANDROID, IOS
- **Languages:** EN, RU
- **Ориентация:** вертикальная и горизонтальная
- **Multiplayer / leaderboards / social:** нет
- **Распространение:** везде, кроме Google Play (туда игра пойдёт напрямую). App Store и RuStore среди партнёров Playgama нет, исключать их не нужно
- **Опубликована в другом месте:** https://apps.apple.com/us/app/rotathree/id6822865159

Игра в консоли: https://developer.playgama.com/applications/cmvglotdo0508lh0hwr7xuc8s (создана 20 октября 2026 года, форма заполнена через сайт).

**Description**

RotaThree is a falling-block puzzle with a twist: four glasses stand around one centre, and pieces fall in all of them at once. The glass on top is active and falls quickly; the others wait and fall slowly. Turn the cross to bring any glass to the top, move and rotate the three-block sticks, and match three cells of one colour in a row — the blocks above drop down and can chain into combos. A 16-level campaign adds colours, glasses and speed step by step, Nightmare opens after it, and Custom mode lets you choose the glasses, colours, arm length and speed yourself.

**How to play**

Keyboard: A and D move the stick, W rotates it, S or Space drops it. The arrow keys turn the cross: Left and Right bring the neighbouring glass to the top, Up or Down the opposite one; clicking a glass brings it up too. Esc or P pauses. On a phone or tablet two on-screen pads do the same. Match three cells of one colour in a row to clear them. A glass that fills to the end of its arm ends the game. The first game starts with a short tutorial, and every key and pad button can be changed in Settings.

**Story**

RotaThree started from a simple question: what if a falling-block puzzle had four wells instead of one, and you could turn the board to choose which one to play? Only the glass on top falls fast, so the real game is deciding when to leave a glass half-built and rescue another. The campaign grew one glass and one colour at a time, until all four glasses fell together. How many glasses can you keep alive at once?

## Загрузка через MCP

Сервер `playgama-developer-console` (`https://developer.playgama.com/api/mcp`), порядок как у RuneChess:

1. `create_application` (title, engine `js`)
2. `start_archive_upload` (имя, размер) → PUT zip на `uploadUrl` с `Content-Type: application/zip` → `confirm_archive_upload` → `get_archive_status`, пока не будет `PASSED` и `bridgeSdk: FOUND`
3. `start_cover_upload` для `square`, `portrait` и `landscape` → PUT PNG → `confirm_cover_upload`
4. `update_application_form` с полями выше
5. `get_archive_qa_tool_link` — QA-инструмент Playgama для архива
6. `publish_sandbox` (сначала спросить разработчика), затем `get_sandbox_share`; открыть опубликованную ссылку и пройти игру, как требует чек-лист
