#!/usr/bin/env bash
set -e

LOADER="/Library/ScriptingAdditions/yabai.osax/Contents/MacOS/loader"

if [ "$EUID" -ne 0 ]; then
    echo "[-] Please run this script with sudo:"
    echo "    sudo $0"
    exit 1
fi

if [ ! -f "$LOADER" ]; then
    echo "[-] $LOADER not found."
    exit 1
fi

echo "[*] Checking PAC ABI capabilities in $LOADER..."
read I O <<< $(otool -f "$LOADER" | awk '/architecture/{i=$2} /capabilities 0x81/{f=1} f&&/offset/{print i, $2; exit}')

if [ -n "$O" ]; then
    echo "[+] Found Sequoia PAC ABI mismatch (caps 0x81 at arch $I, offset $O)."
    echo "[+] Patching to 0x80 for macOS Sequoia compatibility..."
    printf '\x80' | dd of="$LOADER" bs=1 seek=$((8 + I*20 + 4)) count=1 conv=notrunc 2>/dev/null
    printf '\x80' | dd of="$LOADER" bs=1 seek=$((O + 11)) count=1 conv=notrunc 2>/dev/null
    codesign -f -s - "$LOADER" >/dev/null 2>&1
    echo "[+] Successfully patched and resigned $LOADER!"
else
    echo "[+] Loader already has compatible PAC ABI capabilities."
fi

echo "[*] Loading yabai scripting addition..."
yabai --load-sa
echo "[✓] Scripting addition loaded successfully!"
