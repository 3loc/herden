#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd -P "$(dirname "$0")" && pwd)
landing_dir=$(CDPATH='' cd -P "$script_dir/.." && pwd)
source_url="file://$landing_dir/og-card.html"
output="$landing_dir/public/og.png"

if command -v chromium >/dev/null 2>&1; then
    browser=chromium
elif command -v chromium-browser >/dev/null 2>&1; then
    browser=chromium-browser
elif command -v google-chrome >/dev/null 2>&1; then
    browser=google-chrome
else
    printf '%s\n' "A Chromium-based browser is required to render the OpenGraph card." >&2
    exit 1
fi

"$browser" \
    --headless \
    --disable-gpu \
    --hide-scrollbars \
    --no-sandbox \
    --run-all-compositor-stages-before-draw \
    --force-device-scale-factor=1 \
    --window-size=1200,630 \
    --screenshot="$output" \
    "$source_url" >/dev/null 2>&1

printf 'Rendered %s\n' "$output"
