#!/usr/bin/env python3
"""Prepare equal-loudness, faded AAC tracks for Flutter and the browser.

Requires ffmpeg and ffprobe. Originals and license records stay untouched.
Run from anywhere with: python3 tool/prepare_music.py
"""

import json
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'assets/music/playback'
WEB_OUTPUT = ROOT / 'webapp/public/music'
FADE_SECONDS = 2
TARGET_LUFS = -23
TRACKS = [
    ('music/Deep Focus.m4a', 'deep-focus'),
    ('music/Deep Focus(1).m4a', 'deep-focus-1'),
    ('music/downloaded/ambient_relaxing_loop.ogg', 'ambient-relaxing-loop'),
    ('music/downloaded/project_utopia_loop.ogg', 'project-utopia-loop'),
    ('music/downloaded/chill_loopable.mp3', 'chill-loopable'),
    ('music/downloaded/insistent_background_loop.ogg', 'insistent-background-loop'),
    ('music/downloaded/claimed_by_the_void_loop.mp3', 'claimed-by-the-void-loop'),
]


def prepare(source: Path, slug: str) -> dict:
    probe = subprocess.run(
        ['ffprobe', '-v', 'error', '-show_entries', 'format=duration',
         '-of', 'json', str(source)],
        capture_output=True, text=True, check=True,
    )
    duration = float(json.loads(probe.stdout)['format']['duration'])
    if duration < 2 * FADE_SECONDS:
        raise ValueError(f'Track is too short for the fades: {source}')
    analysis = subprocess.run(
        ['ffmpeg', '-hide_banner', '-nostats', '-i', str(source), '-af',
         f'loudnorm=I={TARGET_LUFS}:TP=-2:LRA=11:print_format=json',
         '-f', 'null', '-'],
        capture_output=True, text=True, check=True,
    )
    measured, _ = json.JSONDecoder().raw_decode(analysis.stderr[analysis.stderr.rfind('{'):])
    normalizer = (
        f'loudnorm=I={TARGET_LUFS}:TP=-2:LRA=11:linear=true:'
        f'measured_I={measured["input_i"]}:'
        f'measured_TP={measured["input_tp"]}:'
        f'measured_LRA={measured["input_lra"]}:'
        f'measured_thresh={measured["input_thresh"]}:'
        f'offset={measured["target_offset"]}'
    )
    fade_out = duration - FADE_SECONDS
    filters = f'{normalizer},afade=t=in:d={FADE_SECONDS},afade=t=out:st={fade_out:.6f}:d={FADE_SECONDS}'
    destination = OUTPUT / f'{slug}.m4a'
    subprocess.run(
        ['ffmpeg', '-y', '-hide_banner', '-loglevel', 'error', '-i', str(source),
         '-map', '0:a:0', '-vn', '-af', filters, '-c:a', 'aac', '-b:a', '160k',
         '-ar', '44100', '-ac', '2', '-movflags', '+faststart', str(destination)],
        check=True,
    )
    shutil.copy2(destination, WEB_OUTPUT / destination.name)
    print(f'{slug}: {measured["input_i"]} LUFS -> target {TARGET_LUFS} LUFS, fades {FADE_SECONDS}s', flush=True)
    return {'file': destination.name, 'durationSeconds': duration,
            'sourceLufs': float(measured['input_i'])}


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    WEB_OUTPUT.mkdir(parents=True, exist_ok=True)
    tracks = [prepare(ROOT / 'assets' / source, slug) for source, slug in TRACKS]
    (OUTPUT / 'processing.json').write_text(
        json.dumps({'targetLufs': TARGET_LUFS, 'truePeakDbtp': -2,
                    'fadeInSeconds': FADE_SECONDS, 'fadeOutSeconds': FADE_SECONDS,
                    'tracks': tracks}, indent=2) + '\n', encoding='utf-8',
    )


if __name__ == '__main__':
    main()
