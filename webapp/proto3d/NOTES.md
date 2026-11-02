# 3D RotaThree — prototype notes

A throwaway page to find out whether a 3D RotaThree is playable. It runs on
the dev server only (`npm run dev` in `webapp/`, then
http://localhost:5183/proto3d/); no build includes it. URL parameters:
`centre` (odd, default 7), `arm` (8), `colors` (4), `seed`.
`node proto3d/shots.mjs` plays it with real key presses and retakes
`shots/2d`.

- `rules.js` — the 2D rules of `src/game` in three axes: six glasses around a
  cube of a centre, sticks of three stepping one cell at a time (fast in the
  steered glass, slowly in the others), lock on a blocked step, lines of 3+
  along x, y or z pop, blocks fall down the screen, cascades, game over when a
  glass is full to its far end.
- `main.js` — the view and the keys; blocks are drawn like the game's sprites.

There were two takes.

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

## Take 2: the 2D view (current, `shots/2d`)

Made after review: the screen shows the cross as the 2D game does, and the
third dimension is only hinted at.

- The four glasses around the screen lie in the **middle layer** of a 7³
  centre. Their sticks move and turn only in it, with the 2D keys: A/D, W turns,
  S or Space drops.
- The glasses **in front of and behind** the screen are a faint tunnel at the
  centre. Their sticks are see-through and fly along the line of sight into any
  layer, landing against the far wall of the centre or on what is already
  there. **1–6** picks a glass. A glass around the cross is turned to the top,
  as in 2D. The front or back glass is steered in place: A/D/W/S move its
  stick over the screen, Q/E turn it, Space drops it.
- **← →** turn the cross as in 2D. **↑ ↓** tip the hub so that the glass
  behind or in front comes over the top. The cross fades while the hub
  turns, as the 2D grid does.
- Blocks off the middle layer are see-through hints: by default only the
  nearest behind and the nearest in front of each cell (X cycles: nearest /
  all layers / behind only / none).

What reads well:

- **The cross reads exactly as the 2D game does** (`01`, `02`): same keys,
  same aiming lane and outline.
- **The tumble.** It is understood half-way (`06`).
- **Front and back sticks.** Two frames around the centre show the stick's
  leading face (white) and where it will land (blue), so the gap is how far it
  still has to go. The HUD names the landing layer (`03`, `05`).

What is hard:

- **Perspective gives only ±30% of size.** Alone it does not say how deep a
  see-through stick or block is; the frames and the HUD line do.
- **Other layers.** With every layer shown the centre becomes noise (`08a`).
  Nearest-only is calmer, but after a tumble every row of the old board becomes
  a layer of its own, and the centre is still a crowd of see-through squares
  (`07`). With no hints (`08b`) it is a clean 2D board, and lines along the
  depth come as surprises.
- **A tumble moves your stacks.** A stack the front glass built towards the
  eye becomes a column in the bottom glass after the tumble and ended the game
  there (`10`). That is the 3D thinking the mode is after, but nothing on
  screen warns of it before the tumble.
- **Sticks in flight jump on a tumble.** They are laid flat in the middle layer
  again so that the 2D keys still work.
- **W/S depend on the glass.** They turn and drop for the top glass but move
  the front or back stick. A press made while the board is still resolving is
  read for the glass that was steered before.
- **Keys: 17** — A, D, W, S, Space, Q, E, 1–6, ←→↑↓. ← → do what the digits
  of the side glasses do, and Q/E repeat W, so 13 would do.
- **The centre fills from six sides.** Every glass drops on its own (the 2D
  rule), so careless play ended after 16 sticks (`10`).

## What would make it comfortable

1. **Keep the 2D view.** Carry depth with a small gauge beside the centre
   (layers −3…+3, the steered stick, its landing layer and what is already in
   its columns) rather than with perspective or more see-through squares.
2. **Fewer layers.** Try `?centre=5`, two layers each side. With 7 the front
   glass needs three sticks per column before it reaches the middle layer, and
   the hints crowd.
3. **Preview the tumble.** While ↑/↓ is held, show where the stacks will end
   up, or outline the glass that will come over the top. After a tumble the
   whole board has to be read again.
4. **Slow the front and back glasses.** Make them slower than the side ones,
   or step only when steered, so that the centre does not fill from six sides
   at once. A rule closer to 2D: their sticks stop in the middle layer instead
   of flying through it.
5. **One meaning per key.** Keep Space as the only drop for every glass. Read
   W/S when the input is applied, not when the key is pressed. Consider dropping
   ← → in favour of 1–6, leaving A/D, W, S/Space, Q/E, 1–6, ↑↓.
6. **Tumbled sticks.** Start them again from their rims, or do not allow ↑/↓
   while a steered stick is half-way down, instead of quietly laying it flat.
