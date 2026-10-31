# Sound effects

The game plays one take per group, listed as `CHOSEN` in
`src/services/sounds.ts` and shipped from `public/sfx/`. This folder keeps every
take we tried, so a sound can be changed later without searching again. It is
not part of any build: Vite serves it on the dev server only.

All sources are CC0 (public domain): no attribution is required. Kenney asks for
an optional credit to kenney.nl.

## Trying another take

1. `npm run dev`, then open `/sfx-lab/` on the dev server (next to the game).
2. Press ▶ to hear a take; "Комбо ×1…×6" plays a burst up the scale as the game
   does in a chain. "В игру" makes the game on this computer play that take:
   reload the game's tab.
3. To ship the choice, copy `takes/<take>.mp3` to `public/sfx/` and set it in
   `CHOSEN`; remove the take it replaces from `public/sfx/`.
4. The mobile app plays the same takes from `assets/sfx/`, with `takes` in
   `lib/ui/audio/sound_effects.dart` set as `CHOSEN` is: run
   `python3 -I tool/prepare_app_sfx.py` to copy them there. It also renders the
   burst once per step of the scale, since the app cannot raise the pitch as it
   plays.

Volume: the groups are levelled by `tool/prepare_sfx.py` (buttons and moves
quietest, bursts and the banner loudest); the player's "Громкость звуков"
setting, 30 % by default, scales them all. The quick sound button mutes music
and effects together.

## Rebuilding the takes

`python3 -I tool/prepare_sfx.py <packs> <more packs> <banner packs> webapp/sfx-lab/takes`
needs FFmpeg with libmp3lame. Each pack is unpacked into `<folder>/x/` (single
files go straight into the folder):

| Folder | Pack | Where |
| --- | --- | --- |
| `<packs>/interface` | Kenney Interface Sounds | https://kenney.nl/assets/interface-sounds |
| `<packs>/impact` | Kenney Impact Sounds | https://kenney.nl/assets/impact-sounds |
| `<packs>/jingles` | Kenney Music Jingles | https://kenney.nl/assets/music-jingles |
| `<packs>/digital` | Kenney Digital SFX | https://opengameart.org/content/63-digital-sound-effects-lasers-phasers-space-etc |
| `<packs>/freesound` | `639429-twinkle.mp3` (Crystal Twinkle, LaurenPonder), `735168-lyre.mp3` (Item Pickup Chime, Irolan) | https://freesound.org/people/LaurenPonder/sounds/639429/, https://freesound.org/people/Irolan/sounds/735168/ |
| `<more packs>/popsA` | Pop sounds, EZduzziteh (`pop1.ogg`…) | https://opengameart.org/content/pop-sounds |
| `<more packs>/popsB` | Pop sounds (`pop1.wav`…) | https://opengameart.org/content/pop-sounds-0 |
| `<more packs>/pops3` | 3 Pop Sounds | https://opengameart.org/content/3-pop-sounds |
| `<more packs>/bubbles` | Bubble Sound Effects (`bubbles-single*.wav`, saved as `single*.wav`) | https://opengameart.org/content/bubble-sound-effects |
| `<more packs>/cc0sfx` | 100 CC0 SFX | https://opengameart.org/content/100-cc0-sfx |
| `<more packs>/junkala` | 512 Sound Effects (8-bit style), Juhani Junkala | https://opengameart.org/content/512-sound-effects-8-bit-style |
| `<banner packs>/levelup13` | Level up, power up, Coin get (13 Sounds), WobbleBoxx | https://opengameart.org/content/level-up-power-up-coin-get-13-sounds |
| `<banner packs>/ui7` | 7 Assorted Sound Effects (Menu, Level Up) | https://opengameart.org/content/7-assorted-sound-effects-menu-level-up |
| `<banner packs>/up3` | Up (3x) | https://opengameart.org/content/up-3x |
| `<banner packs>/retro50` | 50 CC0 retro / synth SFX | https://opengameart.org/node/87895 |
| `<banner packs>/scifi` | Kenney Sci-fi Sounds | https://kenney.nl/assets/sci-fi-sounds |

Kenney's site hands out a signed link per download ("Continue without
donating"); the Kenney packs are also mirrored on OpenGameArt.

## Takes

### Buttons (`ui`)

| Take | Source |
| --- | --- |
| `ui-select` | Kenney Interface Sounds, select_001 |
| `ui-select-soft` | Kenney Interface Sounds, select_002 |
| `ui-click` | Kenney Interface Sounds, click_001 |
| `ui-blip` **(in the game)** | Kenney Interface Sounds, drop_001 |

### Stick moved (`move`)

| Take | Source |
| --- | --- |
| `move-click` | Kenney Interface Sounds, click_002 |
| `move-tick` | Kenney Interface Sounds, tick_004 |
| `move-select` **(in the game)** | Kenney Interface Sounds, select_002 |

### Stick rotated (`rotate`)

| Take | Source |
| --- | --- |
| `rotate-bloop` **(in the game)** | Kenney Interface Sounds, drop_002 |
| `rotate-pluck` | Kenney Interface Sounds, pluck_002 |
| `rotate-select` | Kenney Interface Sounds, select_003 |
| `rotate-click` | Kenney Interface Sounds, click_001 |

### Cross turned (`turn`)

| Take | Source |
| --- | --- |
| `turn-sweep-low` | Kenney Interface Sounds, maximize_006 |
| `turn-sweep-deep` **(in the game)** | Kenney Interface Sounds, maximize_008 |
| `turn-switch` | Kenney Interface Sounds, switch_003 |
| `turn-scroll` | Kenney Interface Sounds, scroll_002 |

### Piece landed (`land`)

| Take | Source |
| --- | --- |
| `land-wood` | Kenney Impact Sounds, impactWood_light_000 |
| `land-knock` | Kenney Impact Sounds, impactGeneric_light_000 |
| `land-soft` **(in the game)** | Kenney Impact Sounds, impactSoft_medium_000 |
| `land-bloop` | Kenney Interface Sounds, drop_003 |

### Match burst (raised a step per combo) (`pop`)

| Take | Source |
| --- | --- |
| `pop-bubble-a` | Pop sounds by EZduzziteh, pop5 |
| `pop-bubble-b` | Pop sounds by EZduzziteh, pop7 |
| `pop-bubble-c` | Pop sounds (wav), pop3 |
| `pop-bubble-d` | Pop sounds (wav), pop6 |
| `pop-water` | Bubble Sound Effects, bubbles-single2 |
| `pop-plop` **(in the game)** | 100 CC0 SFX, plop_01 |
| `pop-pop-long` | 3 Pop Sounds, pop1 |
| `pop-coin` | Juhani Junkala, 512 Sound Effects, sfx_coin_double1 |
| `pop-bubble-sparkle` | Pop sounds (wav), pop3 + Crystal Twinkle (LaurenPonder, Freesound) |
| `pop-bubble-chord` | Pop sounds by EZduzziteh, pop5 + Item Pickup Chime (Irolan, Freesound) |

### Level banner (music ducks under it) (`level`)

| Take | Source |
| --- | --- |
| `level-rise-1` | Level up, power up, Coin get (WobbleBoxx), Rise01 |
| `level-rise-2` | Level up, power up, Coin get (WobbleBoxx), Rise02 |
| `level-rise-3` | Level up, power up, Coin get (WobbleBoxx), Rise03 |
| `level-rise-warm` | Level up, power up, Coin get (WobbleBoxx), Rise07 |
| `level-rise-long` | Level up, power up, Coin get (WobbleBoxx), Rise05 |
| `level-upper` | Level up, power up, Coin get (WobbleBoxx), Upper01 |
| `level-level-up` | 7 Assorted Sound Effects (Menu, Level Up), Level Up |
| `level-ability` | 7 Assorted Sound Effects (Menu, Level Up), Ability Learn |
| `level-synth-swell` | 50 CC0 retro / synth SFX, synth_misc_01 |
| `level-synth-pad` | 50 CC0 retro / synth SFX, synth_misc_03 |
| `level-force-field` | Kenney Sci-fi Sounds, forceField_002 |
| `level-up` **(in the game)** | Up (3x), upmid |

### Game over (`over`)

| Take | Source |
| --- | --- |
| `over-digital` **(in the game)** | Kenney Digital SFX, lowDown |
| `over-steel` | Kenney Music Jingles, jingles_STEEL06 |
| `over-pizzicato` | Kenney Music Jingles, jingles_PIZZI03 |
| `over-sax` | Kenney Music Jingles, jingles_SAX07 |
