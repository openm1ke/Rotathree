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
