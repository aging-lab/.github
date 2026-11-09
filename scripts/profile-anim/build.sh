#!/usr/bin/env bash
# Rebuild the animated GIFs used in profile/README.md.
# Requires: Google Chrome, Node 22+, ffmpeg, ImageMagick (magick).
# usage: scripts/profile-anim/build.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/../../profile/assets"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FPS=15      # capture rate
SCALE=1.5   # render at 1.5x, then downscale for anti-aliasing
COLORS=128
FUZZ=0.8%   # inter-frame tolerance; higher values leave visible ghosting (esp. dark theme)

# name  page        width height
JOBS=(
    "virtual-omics vo.html    880 560"
    "blind-spot    genes.html 880 470"
)

for job in "${JOBS[@]}"; do
    read -r name page w h <<<"$job"
    for theme in light dark; do
        frames="$WORK/$name-$theme"
        TMPDIR="$WORK" node "$HERE/capture.mjs" "$HERE/$page" "$theme" "$frames" "$w" "$h" "$FPS" "$SCALE"
        ffmpeg -v error -y -framerate "$FPS" -i "$frames/%04d.png" \
            -vf "scale=${w}:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=${COLORS}:stats_mode=full[p];[b][p]paletteuse=dither=none:diff_mode=rectangle" \
            -loop 0 "$WORK/$name-$theme.raw.gif"
        magick "$WORK/$name-$theme.raw.gif" -fuzz "$FUZZ" -layers Optimize "$OUT/$name-$theme.gif"
        ls -lh "$OUT/$name-$theme.gif" | awk '{print $5, $9}'
    done
done
