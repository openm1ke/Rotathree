# Rotathree

Experimental gameplay prototype: four glasses joined in a cross around a shared
10×10 centre. Each glass is one arm plus the centre. A three-square stick falls
down every glass at the same time, a whole cell per step — once a second in the
glass on top, once every three seconds in the others — through the arm and on
across the centre, until its next step is blocked and it locks. You turn the
cross to bring a glass to the top, aim its stick, turn it (four orientations),
drop it, and line up three or more of a colour: they pop and the blocks above
fall. A glass that fills up to the far end of its arm ends the game.

There are two front ends over the same rules: the Flutter app in this folder
and a browser version for the keyboard in [`webapp/`](webapp/README.md).

**Play in the browser:** https://openm1ke.github.io/Rotathree/ — built from
`webapp/` and published by `.github/workflows/pages.yml` on every push to
`main` that touches it.

See [PROTOTYPE_REPORT.md](PROTOTYPE_REPORT.md) for the rules as implemented,
the architecture, test and playtest results.

## Run

```bash
flutter run
```

The app opens on a menu: **Campaign** (fifteen levels, each a score target with
more glasses and colours), **Custom** (your own game, set up before it starts),
**Statistics** (per mode: points, pieces, matches, the best combo, and the last
runs) and **Settings**. **Insane** opens once the campaign is finished.

Controls are two on-screen D-pads in the bottom corners, the buttons of which
are chosen in Settings. Tapping a glass on the field also brings it to the top.
With a hardware keyboard the defaults are the browser version's: A / D move,
W rotates, S or Space drops, ← / → switch glass, ↑ or ↓ the glass opposite,
Esc or P pauses, N starts again. Everything can be changed in
Settings → Controls.

Settings (saved on the device): the keys and pad buttons, the auto-repeat
timing, the nine block colours with saved palettes, the explosions (a different
one for each length of line, or one for all), the shake and turn duration, and
what is written on the field.

## Checks

```bash
flutter analyze
flutter test
dart run tool/balance_sim.dart          # bot balance simulation
dart run tool/campaign_sim.dart --glasses=2 --colours=4 --profile=average
```

## Layout

- `lib/game` — the engine, pure Dart, no Flutter imports
  (`config`, `model`, `engine`, `state`, `sim`; `session.dart` picks the
  rules of a campaign level, Insane or a custom game)
- `lib/ui` — the Flutter app:
  - `app.dart` — the screens, the route between them, what is kept on the device
  - `menu/` — main menu, campaign, custom setup, statistics, settings, colour picker
  - `game/` — the game screen (campaign flow, pauses, results), HUD, banners
  - `field/` — the field painter and the effects (explosions, shake, turn)
  - `input/` — the D-pads, the pad controller (auto-repeat), the game actions
  - `data/` — settings, key bindings, palettes, progress, statistics, storage
  - `widgets/` — shared controls and the backdrop; styled like the browser
    version (Exo 2 from `assets/fonts`)
- `test/game` — engine unit tests and campaign rules;
  `test/ui` — pads, settings and storage, effects, the game screen (pads,
  campaign levels, pause); `test/widget_test.dart` — the app through its menus
- `tool/balance_sim.dart` — seeded bot games for comparing configurations;
  `tool/campaign_sim.dart` — how long bots of each skill need for the campaign
  targets
- `webapp/` — the browser version (Vite + TypeScript + React), with its own
  port of the engine and its own tests
