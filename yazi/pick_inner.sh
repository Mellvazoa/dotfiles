#!/usr/bin/env bash
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"

PREV_WID="${1:-}"
PREV_APP="${2:-}"
PREV_TITLE="${3:-}"
TMP_FILE="$(mktemp "${TMPDIR:-/tmp}/yazi_pick.XXXXXX")"
trap 'rm -f "$TMP_FILE"' EXIT

cd "$HOME"
yazi --chooser-file="$TMP_FILE" || true

COPIED=0
if [ -s "$TMP_FILE" ]; then
    FILES=()
    while IFS= read -r line || [ -n "$line" ]; do
        [ -n "$line" ] && FILES+=("$line")
    done < "$TMP_FILE"

    if [ "${#FILES[@]}" -gt 0 ]; then
        "$HOME/.local/bin/filecopy" "${FILES[@]}" >/dev/null || true
        COPIED=1
    fi
fi

if [ -n "$PREV_WID" ]; then
    yabai -m window --focus "$PREV_WID" 2>/dev/null || true
fi

# If user invoked picker while a native macOS Open/Save dialog was focused, fill it automatically
if [ "$COPIED" -eq 1 ]; then
    case "$PREV_APP|$PREV_TITLE" in
        *openAndSavePanelService*|*Open*|*Открыть*|*Upload*|*Choose*)
            FILL_SCRIPT="$HOME/.config/yazi/fill_open_panel.sh"
            if [ -x "$FILL_SCRIPT" ]; then
                nohup bash -c "sleep 0.22; '$FILL_SCRIPT'" >/dev/null 2>&1 &
            fi
            ;;
    esac
fi
