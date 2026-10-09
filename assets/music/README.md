# Background music

The game plays the seven files in `playback/` sequentially. The playlist repeats
after the final track. Each file has a two-second fade-in and fade-out baked into
the audio, so switching tracks cannot skip a fade or overlap two full-volume tracks.

Playback files are AAC/M4A for Android, iOS and browsers. They are made from the
original files here and in `downloaded/`; originals are kept unchanged. Source and
license records for downloaded tracks are in `downloaded/SOURCES.md`.

Rebuild with `python3 tool/prepare_music.py` (requires FFmpeg and ffprobe). The script
uses two-pass loudness normalization to -23 LUFS with a -2 dBTP true-peak ceiling,
then applies the fades and copies identical playback files to `webapp/public/music/`.
The processing settings and original loudness measurements are in
`playback/processing.json`.

The volume preference defaults to 10% for new users on both platforms. Saved volume
and enabled/disabled preferences take precedence over this default.
