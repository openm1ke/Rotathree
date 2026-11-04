# Rules parity

`rules-trace.json` is the stored trace that both game engines must reproduce:
the Flutter engine (`lib/game/engine`) and the web engine (`webapp/src/game`).

- The Dart engine is the reference. `test/game/rules_parity_test.dart` replays
  four scripted games, one line of state per action, and hashes each line.
- The web test `webapp/src/tests/parity.test.ts` reads the same file, replays
  the same scripts and must produce the same hashes.
- Both sides draw piece colours and scripted actions from mulberry32 (the web's
  `random.ts`), so the same seed means the same game on both platforms.
- Checkpoints (every 250 actions) hold the full state line for diagnosis.

Regenerate the stored trace only after an intended rules change on the Dart side:

```sh
ROTATHREE_WRITE_PARITY=1 flutter test test/game/rules_parity_test.dart
```

To see every state line from both engines, set `ROTATHREE_PARITY_DUMP` to a
file path when running the Dart test or the web test, then compare the files.

## Cube

`cube-trace.json` is the same for Cube, the 3D mode, the other way round: Cube
was made on the web, so the web rules (`webapp/src/cube/rules.ts`) are the
reference and the Dart port (`lib/cube/rules.dart`) follows them.

- `webapp/src/tests/cubeParity.test.ts` plays four scripted games (moves,
  turns of the cross, tips, the glasses in front and behind, drops) and checks
  them against the stored trace; `test/cube/cube_parity_test.dart` replays them
  in Dart and must produce the same hashes.
- Checkpoints (every 200 actions) hold the full state line.

Regenerate it only after an intended change of Cube's rules on the web side:

```sh
cd webapp && ROTATHREE_WRITE_CUBE_PARITY=1 npx vitest run src/tests/cubeParity.test.ts
```
