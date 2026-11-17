#!/usr/bin/env bash
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"

# Pick target path: prefer /tmp/yazi_last_files, fallback to file URL in NSPasteboard
TARGET_PATH=""
SAVED_FILES=()
if [ -s /tmp/yazi_last_files ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        [ -n "$line" ] && [ -e "$line" ] && SAVED_FILES+=("$line")
    done < /tmp/yazi_last_files
    if [ "${#SAVED_FILES[@]}" -gt 0 ]; then
        TARGET_PATH="${SAVED_FILES[0]}"
    fi
fi

if [ -z "$TARGET_PATH" ]; then
    TARGET_PATH="$(swift -e '
import AppKit
if let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], let first = urls.first {
    print(first.path)
}
' 2>/dev/null || true)"
fi

if [ -z "$TARGET_PATH" ] || [ ! -e "$TARGET_PATH" ]; then
    exit 0
fi

# Temporarily put plain path on clipboard so Cmd+V works regardless of EN/RU keyboard layout
printf '%s' "$TARGET_PATH" | pbcopy

osascript <<'EOF'
tell application "System Events"
    key code 5 using {command down, shift down}
    delay 0.20
    key code 9 using {command down}
    delay 0.14
    key code 36
    delay 0.22
    key code 36
end tell
EOF

# Restore real file object(s) onto clipboard so Cmd+V continues working in Telegram/apps
if [ "${#SAVED_FILES[@]}" -gt 0 ] && [ -x "$HOME/.local/bin/filecopy" ]; then
    "$HOME/.local/bin/filecopy" "${SAVED_FILES[@]}" >/dev/null 2>&1 || true
elif [ -x "$HOME/.local/bin/filecopy" ]; then
    "$HOME/.local/bin/filecopy" "$TARGET_PATH" >/dev/null 2>&1 || true
fi
