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
and a browser version with keyboard and adaptive touch controls in [`webapp/`](webapp/README.md).

**Play in the browser:** https://openm1ke.github.io/Rotathree/ — built from
`webapp/` and published by `.github/workflows/pages.yml` on every push to
`main` that touches it.

See [IMPLEMENTATION_NOTES.md](IMPLEMENTATION_NOTES.md) for current session behavior,
validation and release setup. [PROTOTYPE_REPORT.md](PROTOTYPE_REPORT.md) is the
historical prototype audit, with its original test and playtest results.

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
Esc or P pauses, N starts again. The mobile settings configure the D-pads
and repeat timing; hardware key defaults are retained without a key-binding editor.

Settings (saved on the device): pad buttons, the auto-repeat
timing, the nine block colours with saved palettes, the explosions (a different
one for each length of line, or one for all), the shake and turn duration, and
what is written on the field.

New players get six practical lessons before their first game. Training freezes
automatic falling, requires movement, rotation, a real match and a glass switch,
and can be skipped or replayed from the menu. Practice does not affect statistics.

Games are saved periodically, at significant engine events, on pause and when the
app goes into the background. **Continue** in the main menu restores the run paused.
In pause, **Save and menu** keeps the game; **Finish and menu** records an interrupted
run. System Back opens the pause. A storage failure shows a persistent notice with
a retry button while the app stays usable in memory. Clearing app data clears saves.

## Checks

```bash
flutter analyze
flutter test
dart run tool/balance_sim.dart          # bot balance simulation
dart run tool/campaign_sim.dart --glasses=2 --colours=4 --profile=average # one fixed configuration
dart run tool/campaign_run_sim.dart --games=24 --cap=3600 --profile=average # continuous campaign
flutter run --profile -t tool/frame_bench.dart   # build and raster time of a busy field
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
  targets from an empty board; `tool/campaign_run_sim.dart` runs the continuous
  campaign with retained boards and level transitions; `tool/frame_bench.dart` — frame times of a busy field, still,
  turning and exploding
- `webapp/` — the browser version (Vite + TypeScript + React), with its own
  port of the engine and its own tests

## Android release

Debug builds retain the existing application ID. Release builds require the owner's
publishing ID and release key: copy `android/key.properties.example` to the ignored
`android/key.properties`, then set `ROTATHREE_APPLICATION_ID`. Equivalent environment
variables for signing are documented in [IMPLEMENTATION_NOTES.md](IMPLEMENTATION_NOTES.md).
A release without these values fails explicitly instead of using the debug key.

Pull requests and main pushes run Flutter analysis, tests and a debug APK build, plus
web checks and browser regression tests in `.github/workflows/checks.yml`.
