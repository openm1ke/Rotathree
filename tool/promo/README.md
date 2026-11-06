# Promo studio

Store screenshots and videos, made by the app itself: the real screens,
drawn by their own code at a device's size inside widget tests, their games
played by a script, framed in the look of the key art
(`docs/marketing/keyart`). Nothing is drawn by hand, so a new version of the
game gets new pictures by running the steps again.

From the repository root:

```sh
flutter test tool/promo/promo_test.dart    # raw shots → build/promo/raw
flutter test tool/promo/compose_test.dart  # screenshots → build/promo/store
flutter test tool/promo/reel_test.dart     # raw video frames → build/promo/reel
flutter test tool/promo/video_test.dart    # video frames → build/promo/video
tool/promo/encode.sh                       # MP4s with the game's music → build/promo
```

The first two take about two minutes together; the video takes about fifteen.

`flutter test tool/promo/desktop_test.dart` draws the desktop app's menu,
tutorial, a campaign level, the pause and Cube at the sizes of a computer's
window (1280 × 690 and 1920 × 1040 at 100 %, a MacBook) and of a phone, into
`build/promo/desktop`: to look at while the desktop layout is worked on.

## What is made

| Folder | Size | For |
| --- | --- | --- |
| `store/appstore-iphone-6.9/{ru,en}` | 1320 × 2868 | App Store, 6.9-inch iPhone |
| `store/appstore-ipad-13/{ru,en}` | 2064 × 2752 | App Store, 13-inch iPad |
| `store/rustore-phone/ru`, `store/rustore-tablet/ru` | 1080 × 1920 | RuStore |
| `preview-{ru,en}.mp4` | 886 × 1920, 20 s | App Store app previews |
| `promo-ru.mp4` | 1080 × 1920, 25 s | RuStore (through VK Video), feeds |

Each screenshot has a kicker, a title and a line (`captions.dart`) over the
key art, and under them the game as large as fits: the field enlarged, the
pads under it, the empty room the app leaves between them cut out
(`GameWindow` in `look.dart`; where the field and the pads are on each
device is in `layouts`). Lists — the campaign, the achievements — are shown
from their top.

The screenshots lead with the game of glasses (the cross, a cascade, the
Nightmare, the campaign), then Cube, the settings and the achievements. The
videos go the same way: the cross, its cascades and the Nightmare, then
Cube's play, a tip and a look into its volume; the promo has a title before
and the key art after.

## How the shots are made

- `scenes.dart` opens the app with a player's results in it (seven levels
  and two of Cube's passed, the lessons played), so the campaign and the
  achievements have something to show, and walks it to a screen.
- `players.dart` plays: for every stick it tries each turn and place on a
  copy of the game, plays it out to the end of the cascade, and gives the
  real game the inputs of the best one, one at a time. The flat player also
  chooses which glass to bring on top and keeps the stacks low.
- Of the moments a shot is taken at (a line popping, a cascade), the one
  with the most blocks in play is kept: the games are random, and full
  fields look best.
- `studio.dart` loads Exo 2 and the Material icons (tests draw boxes for
  letters otherwise) and saves what a `RepaintBoundary` shows.
