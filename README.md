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

Controls: swipe the field left / right or tap a glass to switch, drag the stick
in the top glass (or MOVE) to aim, tap to rotate, swipe down (or DROP) to drop.
With a hardware keyboard: ← → move, ↑ rotate, ↓ / space drop, A / D switch.

The slider icon in the top-right corner opens the **LAB** panel: step interval
in the active glass and in the others, arm length, 3 or 4 colours, rule
variants, slow motion and a bot that plays by itself.

## Checks

```bash
flutter analyze
flutter test
dart run tool/balance_sim.dart        # bot balance simulation
```

## Layout

- `lib/game` — the engine, pure Dart, no Flutter imports
  (`config`, `model`, `engine`, `state`, `sim`)
- `lib/ui` — the Flutter screen that draws the engine state and feeds it input
- `test/game` — engine unit tests; `test/widget_test.dart` — screen smoke tests
- `tool/balance_sim.dart` — seeded bot games for comparing configurations
- `webapp/` — the browser version (Vite + TypeScript + React), with its own
  port of the engine and its own tests
