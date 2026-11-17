#!/usr/bin/env bash
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"

# Toggle off ONLY if Yazi Picker is currently visible on the active space
VISIBLE_WID="$(yabai -m query --windows 2>/dev/null | jq -r '.[] | select(.app=="kitty" and .title=="Yazi Picker" and ."is-visible"==true) | .id' | head -n 1 || true)"
if [ -n "${VISIBLE_WID}" ]; then
    yabai -m window "${VISIBLE_WID}" --close 2>/dev/null || true
    pkill -f "kitty --title Yazi Picker" 2>/dev/null || true
    exit 0
fi

# Clean up any lingering/off-space Yazi Picker instances before launching a fresh one
pkill -f "kitty --title Yazi Picker" 2>/dev/null || true
sleep 0.05

PREV_JSON="$(yabai -m query --windows --window 2>/dev/null || true)"
PREV_WID="$(printf '%s' "$PREV_JSON" | jq -r '.id // empty' 2>/dev/null || true)"
PREV_APP="$(printf '%s' "$PREV_JSON" | jq -r '.app // empty' 2>/dev/null || true)"
PREV_TITLE="$(printf '%s' "$PREV_JSON" | jq -r '.title // empty' 2>/dev/null || true)"

INNER="$HOME/.config/yazi/pick_inner.sh"
if [ ! -x "$INNER" ]; then
    INNER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pick_inner.sh"
fi

open -n -a Kitty --args \
    --title "Yazi Picker" \
    -o macos_quit_when_last_window_closed=yes \
    -o confirm_os_window_close=0 \
    -o initial_window_width=1020 \
    -o initial_window_height=640 \
    -o remember_window_size=no \
    "$INNER" "$PREV_WID" "$PREV_APP" "$PREV_TITLE"
