#!/usr/bin/env bash
# Rebuild the animated GIFs used in profile/README.md (en) and profile/README.ko.md (ko).
# Output: profile/assets/<name>-<lang>-<theme>.gif
# Requires: Google Chrome, Node 22+, ffmpeg, ImageMagick (magick).
# usage: scripts/profile-anim/build.sh [lang ...]   (default: en ko)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/../../profile/assets"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [ $# -gt 0 ]; then LANGS=("$@"); else LANGS=(en ko); fi

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
    for lang in "${LANGS[@]}"; do
        for theme in light dark; do
            id="$name-$lang-$theme"
            TMPDIR="$WORK" node "$HERE/capture.mjs" "$HERE/$page" "theme=$theme&lang=$lang" "$WORK/$id" "$w" "$h" "$FPS" "$SCALE"
            ffmpeg -v error -y -framerate "$FPS" -i "$WORK/$id/%04d.png" \
                -vf "scale=${w}:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=${COLORS}:stats_mode=full[p];[b][p]paletteuse=dither=none:diff_mode=rectangle" \
                -loop 0 "$WORK/$id.raw.gif"
            magick "$WORK/$id.raw.gif" -fuzz "$FUZZ" -layers Optimize "$OUT/$id.gif"
            ls -lh "$OUT/$id.gif" | awk '{print $5, $9}'
        done
    done
done
