#!/usr/bin/env bash
# Regenerate the multi-resolution Windows .ico (16/24/32/48/64/128/256 px)
# from the master PNG. Requires ImageMagick ("magick" on PATH).
#
# Run from the repo root:  bash assets/icon/build_windows_ico.sh
set -euo pipefail

src="assets/icon/app_icon.png"
out="windows/runner/resources/app_icon.ico"

magick "$src" -background none \
  \( -clone 0 -resize 16x16 \) \
  \( -clone 0 -resize 24x24 \) \
  \( -clone 0 -resize 32x32 \) \
  \( -clone 0 -resize 48x48 \) \
  \( -clone 0 -resize 64x64 \) \
  \( -clone 0 -resize 128x128 \) \
  \( -clone 0 -resize 256x256 \) \
  -delete 0 -colors 256 "$out"

echo "Wrote $out"
magick identify "$out"
