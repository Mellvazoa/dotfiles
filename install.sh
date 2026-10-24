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

# 2. Make scripts executable
chmod +x "$DOTFILES_DIR"/yabai/scripts/* 2>/dev/null || true
chmod +x "$DOTFILES_DIR"/yabai/auto_fit.py 2>/dev/null || true
chmod +x "$DOTFILES_DIR"/rofi/launcher.py 2>/dev/null || true
chmod +x "$DOTFILES_DIR"/sketchybar/sketchybarrc 2>/dev/null || true

# 3. Build sketchybar C helpers if needed
if [ -d "$DOTFILES_DIR/sketchybar/helpers" ]; then
    echo "[*] Compiling Sketchybar helper binaries..."
    (cd "$DOTFILES_DIR/sketchybar/helpers" && make clean && make)
fi

echo ""
echo "Installation complete!"
echo "To restart services:"
echo "  yabai --restart-service"
echo "  skhd --restart-service"
echo "  sketchybar --reload"
