#!/usr/bin/env bash
set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"

echo "======================================================"
echo "  Arona Soft Lavender macOS Dotfiles Setup"
echo "======================================================"

mkdir -p "$CONFIG_DIR"

backup_and_link() {
    local src="$1"
    local dest="$2"

    if [ -e "$dest" ] || [ -L "$dest" ]; then
        if [ "$(readlink -f "$dest" 2>/dev/null || readlink "$dest" 2>/dev/null)" = "$src" ]; then
            echo "[✓] Already linked: $dest"
            return
        fi
        local backup="${dest}.bak.$(date +%s)"
        echo "[!] Backing up existing $dest -> $backup"
        mv "$dest" "$backup"
    fi

    echo "[+] Linking $src -> $dest"
    ln -s "$src" "$dest"
}

# 1. Symlink configurations
backup_and_link "$DOTFILES_DIR/sketchybar" "$CONFIG_DIR/sketchybar"
backup_and_link "$DOTFILES_DIR/kitty"      "$CONFIG_DIR/kitty"
backup_and_link "$DOTFILES_DIR/yabai"      "$CONFIG_DIR/yabai"
backup_and_link "$DOTFILES_DIR/skhd"       "$CONFIG_DIR/skhd"
backup_and_link "$DOTFILES_DIR/rofi"       "$CONFIG_DIR/rofi"
backup_and_link "$DOTFILES_DIR/borders"    "$CONFIG_DIR/borders"
backup_and_link "$DOTFILES_DIR/fastfetch"  "$CONFIG_DIR/fastfetch"
backup_and_link "$DOTFILES_DIR/theme"      "$CONFIG_DIR/theme"
backup_and_link "$DOTFILES_DIR/yazi"       "$CONFIG_DIR/yazi"

# 2. Make scripts executable
chmod +x "$DOTFILES_DIR"/yabai/scripts/* 2>/dev/null || true
chmod +x "$DOTFILES_DIR"/yazi/*.sh 2>/dev/null || true
chmod +x "$DOTFILES_DIR"/rofi/launcher.py 2>/dev/null || true
chmod +x "$DOTFILES_DIR"/rofi/wifi_menu.py 2>/dev/null || true
chmod +x "$DOTFILES_DIR"/rofi/theme_menu.py 2>/dev/null || true
chmod +x "$DOTFILES_DIR"/rofi/opacity_menu.py 2>/dev/null || true
chmod +x "$DOTFILES_DIR"/theme/theme.py 2>/dev/null || true
chmod +x "$DOTFILES_DIR"/sketchybar/helpers/net_info.py 2>/dev/null || true
chmod +x "$DOTFILES_DIR"/sketchybar/sketchybarrc 2>/dev/null || true
chmod +x "$DOTFILES_DIR"/borders/bordersrc 2>/dev/null || true

# 3. Build sketchybar C helpers if needed
if [ -d "$DOTFILES_DIR/sketchybar/helpers" ]; then
    echo "[*] Compiling Sketchybar helper binaries..."
    (cd "$DOTFILES_DIR/sketchybar/helpers" && make clean && make)
fi

# 4. Build 3D Wallpaper Gallery
if [ -d "$DOTFILES_DIR/wallpaper_gallery" ]; then
    echo "[*] Compiling 3D Wallpaper Gallery..."
    (cd "$DOTFILES_DIR/wallpaper_gallery" && make)
fi

# 5. Build & install OCR + OSD utility
if [ -d "$DOTFILES_DIR/ocr_osd" ]; then
    echo "[*] Compiling OCR + OSD utility..."
    (cd "$DOTFILES_DIR/ocr_osd" && make && make install)
fi

# 6. Build & install PowerMenu & Calendar popups
if [ -d "$DOTFILES_DIR/powermenu" ]; then
    echo "[*] Compiling PowerMenu overlay..."
    (cd "$DOTFILES_DIR/powermenu" && make && make install)
fi
if [ -d "$DOTFILES_DIR/calendar_popup" ]; then
    echo "[*] Compiling Calendar popup..."
    (cd "$DOTFILES_DIR/calendar_popup" && make && make install)
fi

# 7. Build & install Telegram Desktop Music Player
if [ -d "$DOTFILES_DIR/tg_music" ]; then
    echo "[*] Setting up Telegram Desktop Music Player..."
    if [ ! -d "$DOTFILES_DIR/tg_music/.venv" ]; then
        python3 -m venv "$DOTFILES_DIR/tg_music/.venv"
        "$DOTFILES_DIR/tg_music/.venv/bin/pip" install -r "$DOTFILES_DIR/tg_music/requirements.txt"
    fi
    chmod +x "$DOTFILES_DIR/tg_music/tg_sync.py" 2>/dev/null || true
    (cd "$DOTFILES_DIR/tg_music" && make && make install)
fi

# 8. Build & install filecopy (Yazi clipboard helper)
if [ -d "$DOTFILES_DIR/yazi" ]; then
    echo "[*] Compiling filecopy helper for Yazi..."
    (cd "$DOTFILES_DIR/yazi" && make && make install)
fi

# 9. Build & install audio_vol (Multi-Output / Cava volume & OSD helper)
if [ -d "$DOTFILES_DIR/audio_vol" ]; then
    echo "[*] Compiling audio_vol helper..."
    (cd "$DOTFILES_DIR/audio_vol" && make && make install)
fi

echo ""
echo "Installation complete!"
echo "To restart services:"
echo "  yabai --restart-service"
echo "  skhd --restart-service"
echo "  sketchybar --reload"
