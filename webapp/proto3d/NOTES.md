# 3D RotaThree — prototype notes

A throwaway page to find out whether a 3D RotaThree is playable. It runs on
the dev server only (`npm run dev` in `webapp/`, then
http://localhost:5183/proto3d/); no build includes it. URL parameters:
`centre` (odd, default 7), `arm` (8), `colors` (4), `seed`.
`node proto3d/shots.mjs` plays it with real key presses and retakes
`shots/2d`.

- `rules.js` — the 2D rules of `src/game` for six glasses around a cube of a
  centre: sticks of three stepping one cell at a time (fast in the steered
  glass, slowly in the others), lock on a blocked step, lines of 3+ pop,
  blocks fall down the screen, cascades, game over when a glass is full to its
  far end.
- `main.js` — the view, the keys and the settings; blocks are drawn like the
  game's sprites.

There were three takes. The third is the current one.

## Take 1: perspective (commit 9a6acd5, `shots/3d`)

The eye sits above the rim of the active glass and looks down about 30° off
its axis. W/A/S/D move across the glass relative to the screen, Q/E/R turn the
stick about three axes, the arrows tip the hub.

What was hard:

- **Depth.** The height of the stack shows only through perspective size. The
  stick near the rim is large and hides the lanes under it. A landing outline
  on top of blocks of its own colour disappears; a lighter tone fixed that.
  Depth frames and a lane down to the outline helped most (`02`, `03b`).
- **The glass behind the active one.** At 30° the far glass lies right behind
  the active one on screen, so its stick looked as if it were inside the
  active glass. Making everything outside the active glass see-through fixed
  that (`05` vs `05b`).
- **A standing stick seen from above.** Standing, and lying far–near, both
  look like a vertical column on screen (`03a` vs `03b`); only size tells them
  apart. Straight down (0°) a standing stick is one square and heights vanish
  (`10`). At 60° heights read well, but far–near aiming is squashed (`09`).
- **Hub turns.** Half-way the turn reads as one rigid body (`04`), but
  afterwards the whole board has to be read again: columns become rows, and
  blocks that rested now stick out sideways (`05`). Nothing falls on a turn
  (the 2D rule).
- **Keys: 12** — 4 moves, 3 turns (+Shift for the other way), drop, 4 hub
  turns, plus toggles. Q and E each do nothing to one of the two lying
  orientations, so a wrong guess is a wasted press. Reversing the colour order
  takes two presses.
- **A 4×4 cross-section fills fast:** careless play ended after ~20 sticks.

## Take 2: the 2D view with see-through layers (commit c776ba2)

The cross as the 2D game shows it, the side glasses' sticks in the middle
layer of a 7³ centre, the glasses in front and behind steered in place with
1–6, ↑/↓ tipping the hub. Lines popped along x, y or z anywhere in the cube.
The other layers were shown as see-through blocks, and the sticks in front and
behind as see-through sticks. Its photographs are in `shots/2d` of that commit.

What was hard: the see-through sticks and layers. With every layer shown the
centre was noise; even nearest-only it was a crowd after a tumble; with none,
lines along the depth popped out of nowhere. A stack the front glass built
towards the eye became a column in the bottom glass after a tumble and ended
the game there with no warning.

## Take 3: the game on the picture (current, `shots/2d`)

After review the rules follow what the screen shows.

- **The picture.** The hub seen along the line of sight: each cell shows the
  nearest block behind it, drawn solid as in 2D. Nothing is see-through
  (`01`).
- **Sticks of the side glasses** live in the middle layer and stop on whatever
  the picture shows, at any depth. The 2D keys: A/D, W turns, S or Space drops
  (`02`).
- **Lines pop in the picture**: three or more of a colour across or up the
  screen, whatever their depths. Popping a block shows what was behind it.
- **Falling is in the picture too.** In the glass on top, a cell that shows
  something falls down the screen to the next one that does, taking
  everything behind it along. The other glasses never move, as in 2D.
- **Front and back glasses** (4 and 3 at the start) are steered in
  place. A/D/W/S move the stick over the screen, Q/E turn it, Space drops it.
  It flies along the line of sight onto whatever is in its cells: the front
  one lands in front and is seen, the back one hides behind. The steered stick
  is an outline over the picture. The panel says where it will land: «сядет
  в слой +2, будет видна» (`03`, `04`).
- **Tipping the hub over (↑/↓)** shows it from another side. What was depth
  becomes up or across, and the new picture settles and pops. Columns built
  from the top become, after ↑, the bottom line made of their top blocks
  (`07` → `08` → `09`). ← → turn the cross in the screen as in 2D: nothing
  falls.
- **V (held)** opens the depth up to look at (`05`); so does every tumble,
  half-way (`08`).
- **Settings panel** (bottom right, kept between visits):
  - the sticks in front and behind that are not steered (T): off by default
    (`06` with them on);
  - the other glasses dropping on their own (I);
  - the aiming lane (G).

What reads well:

- **It is the 2D game while nothing tips.** A clean board, the same keys,
  lines that pop where you see them (`10`).
- **A tumble does what one expects.** The tops of the old stacks come down as
  the bottom line, and a pop shows the colour that was waiting behind. Holding
  V answers "what is behind this?" without cluttering the board.
- **Careless scripted play lasted 34 sticks** (`11`).

What is still hard:

- **A front or back stick is aimed half blind.** Its landing spot covers the
  cells it is over, so only the panel line says how deep it lands and whether
  it will be seen. The outline tints the blocks under it.
- **Popping is not seeing.** A popped cell may show another colour at once,
  from behind, and set off a cascade the player did not plan. Fun, but hard to
  read; V helps.
- **Lines along the depth never pop until a tumble turns them across the
  screen.** Then they pop at once, which can surprise.
- **W/S depend on the glass.** They turn and drop for the top one, move for
  the front or back one.
- **Keys: 17**, a minimal set 13 (A, D, W, S, Space, 1–6, ↑↓), plus V to look.

## What would make it comfortable

1. **Keep the game on the picture.** The 2D board stays readable, and the
   depth matters only when tipping and popping reveal it.
2. **Show the front or back stick's landing in the picture.** Mark the cells
   it will cover with a small corner badge: seen, or hidden behind. That would
   replace the panel line.
3. **Preview a tumble.** While ↑/↓ is held, show the picture as it will be,
   so that what pops after it can be planned.
4. **Mark cells with more behind them.** A small dot for "something is
   behind" would tell where a pop will reveal a colour, with no see-through
   blocks.
5. **Slow the front and back glasses,** or make them step only when steered,
   so that the centre does not fill from six sides at once.
6. **One meaning per key.** Keep Space as the only drop for every glass and
   read W/S when the input is applied; drop ← → in favour of 1–6.
