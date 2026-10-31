"""Builds every take of the game's sound effects from downloaded CC0 packs.

Every output is a mono MP3 (Playgama asks for ogg or mp3), trimmed, faded and
brought to its group's loudness with a static gain, so the game balances the
groups in code and every take of a group is equally loud. The takes and
catalog.json (each take's source) go to webapp/sfx-lab/takes; the game ships
only the chosen ones, copied to webapp/public/sfx. The packs and where each one
comes from are listed in webapp/sfx-lab/README.md.

usage: python3 -I tool/prepare_sfx.py <packs> <more packs> <banner packs> webapp/sfx-lab/takes
"""
import json, re, subprocess, sys
from pathlib import Path

src, more, banner, out = (Path(a) for a in sys.argv[1:5])
out.mkdir(parents=True, exist_ok=True)
UI = src / 'interface/x/Audio'
IMPACT = src / 'impact/x/Audio'
JINGLES = src / 'jingles/x/Audio'
DIGITAL = next((src / 'digital/x').rglob('pepSound1.mp3')).parent
FS = src / 'freesound'

WARM = 'highpass=f=90,lowpass=f=9000,equalizer=f=5000:t=q:w=1:g=-4,lowshelf=f=300:g=2'
LOUD = {'ui': -26, 'move': -28, 'rotate': -24, 'turn': -24, 'land': -22, 'pop': -18, 'level': -19, 'over': -18}

def loudness(path):
    r = subprocess.run(['ffmpeg', '-nostats', '-i', str(path), '-af', 'apad=whole_dur=3,ebur128=peak=true', '-f', 'null', '-'],
                       capture_output=True, text=True)
    m = re.findall(r'I:\s+(-?[\d.]+) LUFS', r.stderr)
    return float(m[-1]) if m else -30.0

made = {}
def render(group, name, inputs, chain='highpass=f=60', length=None, mix=None, fade=0.05, source=''):
    tmp = out / f'.{group}-{name}.wav'
    args = ['ffmpeg', '-v', 'error', '-y']
    for i in inputs:
        args += ['-i', str(i)]
    if len(inputs) > 1:
        pre = ''.join(f'[{k}:a]aformat=channel_layouts=mono,aresample=44100[a{k}];' for k in range(len(inputs)))
        graph = pre + ''.join(f'[a{k}]' for k in range(len(inputs))) + \
            f'amix=inputs={len(inputs)}:duration=longest:normalize=0:weights={" ".join(map(str, mix))},{chain}'
        flag = '-filter_complex'
    else:
        graph, flag = f'aformat=channel_layouts=mono,aresample=44100,{chain}', '-af'
    if length:
        graph += f',atrim=0:{length}'
    graph += f',silenceremove=start_periods=1:start_threshold=-50dB,areverse,' \
             f'silenceremove=start_periods=1:start_threshold=-60dB,afade=t=in:d={fade},areverse'
    subprocess.run(args + [flag, graph, str(tmp)], check=True)
    gain = LOUD[group] - loudness(tmp)
    dest = out / f'{group}-{name}.mp3'
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', str(tmp), '-af', f'volume={gain:.2f}dB,alimiter=limit=0.89',
                    '-c:a', 'libmp3lame', '-b:a', '128k', str(dest)], check=True)
    tmp.unlink()
    made.setdefault(group, []).append({'file': dest.name, 'source': source})

# Buttons of the menus and dialogs.
render('ui', 'select', [UI / 'select_001.ogg'], source='Kenney Interface Sounds, select_001')
render('ui', 'select-soft', [UI / 'select_002.ogg'], source='Kenney Interface Sounds, select_002')
render('ui', 'click', [UI / 'click_001.ogg'], source='Kenney Interface Sounds, click_001')
render('ui', 'blip', [UI / 'drop_001.ogg'], source='Kenney Interface Sounds, drop_001')
# A stick moved left or right (frequent: kept quiet).
render('move', 'click', [UI / 'click_002.ogg'], fade=0.005, source='Kenney Interface Sounds, click_002')
render('move', 'tick', [UI / 'tick_004.ogg'], fade=0.01, source='Kenney Interface Sounds, tick_004')
render('move', 'select', [UI / 'select_002.ogg'], source='Kenney Interface Sounds, select_002')
# A stick rotated.
render('rotate', 'bloop', [UI / 'drop_002.ogg'], source='Kenney Interface Sounds, drop_002')
render('rotate', 'pluck', [UI / 'pluck_002.ogg'], source='Kenney Interface Sounds, pluck_002')
render('rotate', 'select', [UI / 'select_003.ogg'], source='Kenney Interface Sounds, select_003')
render('rotate', 'click', [UI / 'click_001.ogg'], source='Kenney Interface Sounds, click_001')
# The cross turned to another glass.
render('turn', 'sweep-low', [UI / 'maximize_006.ogg'], source='Kenney Interface Sounds, maximize_006')
render('turn', 'sweep-deep', [UI / 'maximize_008.ogg'], source='Kenney Interface Sounds, maximize_008')
render('turn', 'switch', [UI / 'switch_003.ogg'], source='Kenney Interface Sounds, switch_003')
render('turn', 'scroll', [UI / 'scroll_002.ogg'], length=0.45, fade=0.15, source='Kenney Interface Sounds, scroll_002')
# A piece landed.
render('land', 'wood', [IMPACT / 'impactWood_light_000.ogg'], source='Kenney Impact Sounds, impactWood_light_000')
render('land', 'knock', [IMPACT / 'impactGeneric_light_000.ogg'], source='Kenney Impact Sounds, impactGeneric_light_000')
render('land', 'soft', [IMPACT / 'impactSoft_medium_000.ogg'], source='Kenney Impact Sounds, impactSoft_medium_000')
render('land', 'bloop', [UI / 'drop_003.ogg'], source='Kenney Interface Sounds, drop_003')
# A match bursts (the game raises it a step for each combo): round pops.
twinkle, lyre = FS / '639429-twinkle.mp3', FS / '735168-lyre.mp3'
COINS = next((more / 'junkala/x').rglob('sfx_coin_double1.wav'))
POPS3 = next((more / 'pops3/x').rglob('pop1.ogg'))
PLOP = next((more / 'cc0sfx/x').rglob('plop_01.ogg'))
for name, path, source in [
    ('bubble-a', more / 'popsA/pop5.ogg', 'Pop sounds by EZduzziteh, pop5'),
    ('bubble-b', more / 'popsA/pop7.ogg', 'Pop sounds by EZduzziteh, pop7'),
    ('bubble-c', more / 'popsB/pop3.wav', 'Pop sounds (wav), pop3'),
    ('bubble-d', more / 'popsB/pop6.wav', 'Pop sounds (wav), pop6'),
    ('water', more / 'bubbles/single2.wav', 'Bubble Sound Effects, bubbles-single2'),
    ('plop', PLOP, '100 CC0 SFX, plop_01'),
    ('pop-long', POPS3, '3 Pop Sounds, pop1'),
    ('coin', COINS, 'Juhani Junkala, 512 Sound Effects, sfx_coin_double1'),
]:
    render('pop', name, [path], fade=0.03, source=source)
render('pop', 'bubble-sparkle', [more / 'popsB/pop3.wav', twinkle], length=0.7, mix=[1, 0.15], fade=0.25,
       source='Pop sounds (wav), pop3 + Crystal Twinkle (LaurenPonder, Freesound)')
render('pop', 'bubble-chord', [more / 'popsA/pop5.ogg', lyre], length=0.7, mix=[1, 0.4], fade=0.25,
       source='Pop sounds by EZduzziteh, pop5 + Item Pickup Chime (Irolan, Freesound)')
# A level is complete: a short electronic swell under the banner (the music
# steps aside meanwhile). Longer takes are cut to the banner's 2.2 s.
RISE = banner / 'levelup13/x'
UI7 = banner / 'ui7/x'
RETRO = next((banner / 'retro50/x').rglob('synth_misc_01.ogg')).parent
SCIFI = next((banner / 'scifi/x').rglob('forceField_002.ogg')).parent
UP = next((banner / 'up3/x').rglob('upmid.wav')).parent
for name, path, source in [
    ('rise-1', RISE / 'Rise01.aif', 'Level up, power up, Coin get (WobbleBoxx), Rise01'),
    ('rise-2', RISE / 'Rise02.aif', 'Level up, power up, Coin get (WobbleBoxx), Rise02'),
    ('rise-3', RISE / 'Rise03.aif', 'Level up, power up, Coin get (WobbleBoxx), Rise03'),
    ('rise-warm', RISE / 'Rise07.aif', 'Level up, power up, Coin get (WobbleBoxx), Rise07'),
    ('rise-long', RISE / 'Rise05.aif', 'Level up, power up, Coin get (WobbleBoxx), Rise05'),
    ('upper', RISE / 'Upper01.aif', 'Level up, power up, Coin get (WobbleBoxx), Upper01'),
    ('level-up', next(UI7.rglob('Level Up.mp3')), '7 Assorted Sound Effects (Menu, Level Up), Level Up'),
    ('ability', next(UI7.rglob('Ability Learn.mp3')), '7 Assorted Sound Effects (Menu, Level Up), Ability Learn'),
    ('synth-swell', RETRO / 'synth_misc_01.ogg', '50 CC0 retro / synth SFX, synth_misc_01'),
    ('synth-pad', RETRO / 'synth_misc_03.ogg', '50 CC0 retro / synth SFX, synth_misc_03'),
    ('force-field', SCIFI / 'forceField_002.ogg', 'Kenney Sci-fi Sounds, forceField_002'),
    ('up', UP / 'upmid.wav', 'Up (3x), upmid'),
]:
    render('level', name, [path], length=2.2, fade=0.6, source=source)
# The game is lost.
render('over', 'digital', [DIGITAL / 'lowDown.mp3'], fade=0.15, source='Kenney Digital SFX, lowDown')
for name, path in [('steel', 'Steel jingles/jingles_STEEL06.ogg'), ('pizzicato', 'Pizzicato jingles/jingles_PIZZI03.ogg'),
                   ('sax', 'Sax jingles/jingles_SAX07.ogg')]:
    render('over', name, [JINGLES / path], fade=0.2, source=f'Kenney Music Jingles, {Path(path).stem}')

json.dump(made, open(out / 'catalog.json', 'w'), indent=1, ensure_ascii=False)
print(sum(len(v) for v in made.values()), 'files')
