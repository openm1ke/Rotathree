#!/bin/sh
# Encodes each folder of frames in build/promo/video into an MP4 beside it,
# with the game's own music: H.264 at 30 fps and stereo AAC, as App Store
# previews and RuStore ask. See tool/promo/README.md.
set -e
cd "$(dirname "$0")/../.."
music=assets/music/playback/chill-loopable.m4a
for dir in build/promo/video/*/; do
  name=$(basename "$dir")
  frames=$(ls "$dir" | wc -l | tr -d ' ')
  seconds=$(echo "$frames / 30" | bc -l)
  fade_out=$(echo "$seconds - 2" | bc -l)
  ffmpeg -y -loglevel error -framerate 30 -i "$dir/%04d.png" -ss 8 -t "$seconds" -i "$music" \
    -filter_complex "[1:a]afade=t=in:st=0:d=1,afade=t=out:st=$fade_out:d=2,loudnorm=I=-18:TP=-2[a]" \
    -map 0:v -map "[a]" -c:v libx264 -profile:v high -pix_fmt yuv420p -crf 18 -r 30 \
    -c:a aac -b:a 256k -ar 48000 -ac 2 -shortest -movflags +faststart "build/promo/$name.mp4"
  echo "build/promo/$name.mp4: $frames frames"
done
