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
  nearest block behind it, drawn solid as in 2D. Nothing is see-through.
  The flat picture is drawn straight on (an orthographic eye), so no block
  shows a side however far it is from the middle; the eye eases into
  perspective only while the hub is open.
- **The blocks** are cubes with rounded edges. Face on, each one is the 2D
  sprite: a rounded rim graded from light at the top of the screen to dark at
  the bottom, a flat face of the plain colour with a shine across its top,
  and a narrow gap between tiles. Open, they read as solid rounded cubes,
  faces turned from the eye a little darker. A
  small square in a corner of a cell gives the colour of the block behind it:
  what a pop there would show (`01`).
- **Sticks of the side glasses** live in the middle layer and stop on whatever
  the picture shows, at any depth (`02`). A stick turns as one body about its
  middle square, its tiles turning with it (`02b`).
- **Lines pop in the picture**: three or more of a colour across or up the
  screen, whatever their depths. Popping a block shows what was behind it.
- **Falling is in the picture too.** In the glass on top, a cell that shows
  something falls down the screen to the next one that does, taking
  everything behind it along. The other glasses never move, as in 2D.
- **Front and back glasses** (4 and 3 at the start) are steered in place and
  wait until they are. A stick flies along the line of sight onto whatever is
  in its cells: the front one lands in front and is seen, the back one hides
  behind. The steered stick is an outline over the picture with a mark in each
  square: its colour if that square will be seen, a dark hole if it will hide.
  The panel says the layer: «сядет в слой −3, видно 1 из 3» (`03`, `04`).
- **Tipping the hub over (↑/↓).** Holding the key shows the picture as it
  would settle, with what would pop blinking; the panel counts it (`09`,
  `11`). Letting go tips it; Esc puts it back. What was depth becomes up or
  across: columns built from the top become, after ↑, the bottom line made
  of their top blocks (`07` → `08` → `09` → `10`).
- **The change of side is a real turn.** The hub leans over as one body,
  like a tower of blocks tipping the way the arrow says, and opens up into
  depth half-way before landing flat on its new side (`08`). The game holds
  still for the 0.65 s it takes. The sticks in flight turn with it as one
  body with the blocks, those of the glasses in front and behind too, solid,
  as they are whenever the hub is open (`08`) — all but those of the glasses
  on the tip's axis (left and right for ↑/↓): they stay on the screen as they
  are, upright, and the rules lay them in just those cells on the new side,
  so they never turn at all. A stick the flat picture stops showing — the top
  one going in front of the eye, the bottom one behind — fades out as the hub
  leans, and the one that takes its place (from behind, or from in front)
  fades in at the same pace. A stick the tip lays some other way (one that
  pointed at the eye after a turn of the cross) turns flat on the screen as
  the hub leans, from the way it lay to the way it will lie, so it never
  shows end on and needs no turn after (`10b`). ← → move no stick: each goes
  round with its glass, as in 2D. The preview shows them where
  the tip lays them (`09`); a stick laid somewhere else slides and turns there
  once the hub has landed, rather than jumping. (A wave of cubes each rolling over to its
  new colour was tried in its place and dropped on review: it read as window
  blinds, not as the hub turning.)
- **V (held)** opens the depth up to look at (`05`). With V held, W/A/S/D
  choose where from: above or below, the right or the left (`14`, from below
  and the left).
- **Pause = a look around.** While paused, ← → ↑ ↓ and Q E turn the hub any
  way to be looked at: about the screen's upright, its horizontal or the line
  of sight. Nothing in the game changes, the blocks that would make lines
  from that side blink, and the panel counts them (`12`; in the open with V,
  `13`). Every stick in flight is there, solid, turning with the hub; on the
  flat paused picture the sticks in front and behind show as outlines
  whatever the setting. Esc or going on rolls it back to where the game is;
  the play keys rest meanwhile. Once the game is over the same keys look around at once,
  to see how it was lost; the banner hides while the hub is turned or V is
  held, and a setting (K) hides it for good (`18`).
- **Keys, one meaning each.**
  - A/D move left and right.
  - W turns the stick on top, as in 2D, and moves a front or back stick up.
  - S moves any stick one cell down; it never drops.
  - Space drops, for every glass.
  - Q/E turn.
  - 1–6 take a glass: a side one is turned to the top as in 2D.
  - ← → turn the cross in the screen as in 2D; nothing falls.
  - ↑/↓ tip the hub.

  W and S are read when they are applied, so a press made while the board
  resolves counts for the glass steered then. ← → were taken out for a
  moment in favour of the number keys and put back on review: the user turns
  the cross with them. 17 keys, plus V to look and Esc.
- **Settings panel** (bottom right, kept between visits):
  - show the front and back sticks that are not steered (T), off (`06` with
    them on);
  - let those glasses fall on their own, every 6 s (Y), off;
  - the other glasses dropping on their own (I), on;
  - the colour-behind marks (B), on;
  - the edges of the hub (O) and the glasses' numbers (L), both off: it
    looks like the 2D game, and the other glasses are kept in mind (`15` has
    them off);
  - the aiming lane (G), on;
  - the game-over banner (K), on.

What reads well:

- **It is the 2D game while nothing tips.** A clean board, the same keys,
  lines that pop where you see them (`16`).
- **Depth shows only as marks and on request.** The colour-behind mark says
  what a pop will reveal. The landing marks say whether a front or back stick
  will be seen. Holding ↑/↓ says what a tip will do, and V shows the whole
  thing — all without see-through blocks.
- **A tumble does what one expects**, and can now be planned: the preview of
  a busy board shows the six blocks a tip would pop (`11`).
- **Careless scripted play lasted 34 sticks** (`17`).

What is still open:

- **A preview costs a moment.** A tap of ↑/↓ still tips at once, but holding
  it to look lets the stick on top keep falling.
- **Lines along the depth never pop until a tumble turns them across the
  screen.** The preview shows them coming now, but not before ↑/↓ is held.
- **Marks.** The colour-behind mark is one level deep: what lies further back
  is seen only with V.
- **Size.** A centre of 7 with arms of 8 was not compared with 5 or 9 by hand
  (`?centre=5`).
