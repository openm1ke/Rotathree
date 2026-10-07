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

The app opens on a menu: **Играть** (one run for survival), **Дзен** (the same
game through levels — reach a level's score, watch it celebrated, play on) and
**Настройки**.

Controls are two on-screen D-pads in the bottom corners. By default the left
one steers the piece (left / right, soft drop down, hard drop up) and the
right one turns things (rotate up / down, switch glass left / right, the glass
opposite in the middle). What every button does is chosen in the settings.
Tapping a glass on the field also brings it to the top. With a hardware
keyboard: ← → move, ↑ / X and Z rotate, ↓ soft drop, space drop, A / D / S
switch glass, Esc pause.

Settings (saved on the device): the pads and auto-repeat; step intervals, arm
length, 1–3 extra glasses, 3–6 colours and rule variants; turn duration, shake
and what is written on the field.

## Checks

```bash
flutter analyze
flutter test
dart run tool/balance_sim.dart        # bot balance simulation
```

## Layout

- `lib/game` — the engine, pure Dart, no Flutter imports
  (`config`, `model`, `engine`, `state`, `sim`)
- `lib/ui` — the Flutter app: menu, game screen, settings, the field painter
  and its effects, the pads; styled like the browser version (Exo 2 from
  `assets/fonts`)
- `test/game` — engine unit tests; `test/ui` — pads, settings, effects;
  `test/widget_test.dart` — the app driven through its screens
- `tool/balance_sim.dart` — seeded bot games for comparing configurations
- `webapp/` — the browser version (Vite + TypeScript + React), with its own
  port of the engine and its own tests
