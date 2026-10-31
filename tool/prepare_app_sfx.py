"""Copies the web version's sound effects into the app, assets/sfx.

The takes are the ones the web version ships in webapp/public/sfx (chosen in
webapp/src/services/sounds.ts). A chain of matches climbs the scale: the web
version raises the burst's pitch with the playback rate, which the app's
players cannot do on every platform, so the burst is rendered once per step of
the scale here, pitch and length changed together as a faster playback would.

Android's sound pool cannot load a take of only a few MP3 frames: once the
decoder drops the codec's delay nothing is left, and the take stays silent (the
40 ms move did). A shorter take gets silence after it, up to MIN_SECONDS.

usage: python3 -I tool/prepare_app_sfx.py
"""
import re, shutil, subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WEB = ROOT / 'webapp/public/sfx'
OUT = ROOT / 'assets/sfx'
# Steps of a major scale, as COMBO_STEPS in webapp/src/services/sounds.ts.
STEPS = [0, 2, 4, 5, 7, 9, 11, 12]
MIN_SECONDS = 0.15


def seconds(path):
    return float(subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', str(path)],
                                capture_output=True, text=True, check=True).stdout)


def encode(source, target, filters=''):
    pad = f'apad=whole_dur={MIN_SECONDS}'
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', str(source), '-af', f'{filters},{pad}' if filters else pad,
                    '-ac', '1', '-c:a', 'libmp3lame', '-b:a', '128k', str(target)], check=True)


chosen = dict(re.findall(r"^\s+(\w+): '([\w-]+)',$", (ROOT / 'webapp/src/services/sounds.ts').read_text(), re.M))
OUT.mkdir(parents=True, exist_ok=True)
for old in OUT.glob('*.mp3'):
    old.unlink()
for group, take in chosen.items():
    if group == 'pop':
        continue
    source = WEB / f'{take}.mp3'
    if seconds(source) < MIN_SECONDS:
        encode(source, OUT / f'{take}.mp3')
    else:
        shutil.copyfile(source, OUT / f'{take}.mp3')
pop = WEB / f"{chosen['pop']}.mp3"
for step in STEPS:
    encode(pop, OUT / f"{chosen['pop']}-{step}.mp3", f'asetrate={44100 * 2 ** (step / 12):.3f},aresample=44100')
print('\n'.join(sorted(path.name for path in OUT.glob('*.mp3'))))
