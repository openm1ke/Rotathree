# RotaThree key art

A fantasy on the game rather than a picture of it, in the light of the 1980s
films of glowing lines. The eye stands at the upper edge of a glass drawn only
by its edges and looks down into it: sticks of three cubes of light fall with
trails behind them, the glass goes down through a glowing coordinate plane,
and through its grid the stack below glows and waits, the outline of where the
next stick will land on top of it. Under the plane the stack is the centre of
more glasses that go off to the sides and down, each with a stick of its own:
ours is only one way in. About the glass, walls of light left by racers and
pixels rising off the plane. The cubes keep the game's classic colours, their
edges bright in their own colour rather than burning white; the wordmark is set
in Exo 2 as in the game.

| File | Size | For |
| --- | --- | --- |
| `rotathree-keyart-16x9-{en,ru,none}.png` | 3840 × 2160 | Playgama's landscape cover, banners, YouTube, the trailer's end card |
| `rotathree-keyart-9x16-{en,ru,none}.png` | 2160 × 3840 | Playgama's portrait cover, Shorts, Reels, stories |
| `rotathree-keyart-1x1-{en,ru,none}.png` | 2160 × 2160 | Square covers, social posts |
| `rotathree-keyart-feature-{en,ru}.png` | 1024 × 500 | Google Play's feature graphic |

`en` carries "Turn the glass. Match three.", `ru` "Поверни стакан. Собери три.",
and `none` has no words, for platforms that set their own.

## Rendering again

The scene is `webapp/promo-lab/` (`keyart.js`, three.js, a dev-only page that
no build includes). In `webapp/`:

```
node promo-lab/render.mjs            # every format
node promo-lab/render.mjs 16x9 1x1   # some of them
```

It starts Vite, opens `promo-lab/?format=…&text=…` in Chrome and saves the
PNGs here. On the dev server the page can be looked at directly:
`/promo-lab/?format=9x16&text=ru`. The camera of each format is in `VIEWS`,
the stack in `LAYERS`, the falling sticks in `falling`.
