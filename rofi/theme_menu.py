#!/usr/bin/env python3
"""Interactive preset & dynamic theme switcher powered by choose + theme.py."""
import json
import os
import subprocess
import sys
from choose_overlay import run_choose

CONFIG_DIR = os.path.dirname(os.path.abspath(__file__))
THEME_PY = os.path.expanduser("~/.config/theme/theme.py")
if not os.path.exists(THEME_PY):
    THEME_PY = os.path.abspath(os.path.join(CONFIG_DIR, "..", "theme", "theme.py"))


def get_theme_colors():
    theme_path = os.path.expanduser("~/.config/rofi/colors.json")
    bg_color = "353058"
    text_color = "e4d2fd"
    if os.path.exists(theme_path):
        try:
            with open(theme_path, "r", encoding="utf-8") as f:
                t = json.load(f)
                bg_color = t.get("bg", bg_color)
                text_color = t.get("accent_light", text_color)
        except Exception:
            pass
    return bg_color, text_color


def load_theme_list():
    out = subprocess.check_output(
        [sys.executable, THEME_PY, "--list", "--json"],
        text=True,
    )
    return json.loads(out)


def main():
    if not os.path.exists(THEME_PY):
        sys.exit(1)

    data = load_theme_list()
    state = data.get("state", {})
    presets = data.get("presets", [])

    mode = state.get("mode", "wallpaper")
    active_preset = state.get("preset", "")
    locked = bool(state.get("locked", False))

    entries = []
    item_map = {}

    auto_badge = " [active]" if mode == "wallpaper" else ""
    auto_line = f"󰸉  Auto · Wallpaper Palette{auto_badge}"
    entries.append(auto_line)
    item_map[auto_line] = ("auto", None)

    if mode == "preset":
        lock_line = (
            "  Preset Locked (Wallpaper won't override) -> Unlock"
            if locked
            else "  Preset Unlocked (Wallpaper updates theme) -> Lock"
        )
        entries.append(lock_line)
        item_map[lock_line] = ("toggle_lock", None)

    for p in presets:
        pid = p["id"]
        is_active = mode == "preset" and active_preset == pid
        mark = "●" if is_active else "○"
        lock_suffix = " [locked]" if (is_active and locked) else (" [active]" if is_active else "")
        line = f"{mark}  {p['name']:<22s}  {p['accent']}  ({p['appearance']}){lock_suffix}"
        entries.append(line)
        item_map[line] = ("preset", pid)

    tg_line = "  Open Telegram Palette (Kitty.palette)"
    entries.append(tg_line)
    item_map[tg_line] = ("telegram", None)

    bg, fg = get_theme_colors()
    choose_cmd = [
        "/opt/homebrew/bin/choose",
        "-p", "Select Theme Preset...",
        "-n", "14",
        "-w", "54",
        "-s", "15",
        "-f", "JetBrainsMono Nerd Font",
        "-b", bg,
        "-c", fg,
        "-u",
        "-z",
        "-a",
    ]

    selected = run_choose(choose_cmd, "\n".join(entries))
    if not selected or selected not in item_map:
        sys.exit(0)

    kind, target = item_map[selected]
    if kind == "auto":
        subprocess.run([sys.executable, THEME_PY, "--auto"], check=False)
    elif kind == "toggle_lock":
        subprocess.run([sys.executable, THEME_PY, "--toggle-lock"], check=False)
    elif kind == "preset" and target:
        cmd = [sys.executable, THEME_PY, "--preset", target]
        if locked:
            cmd.append("--lock")
        subprocess.run(cmd, check=False)
    elif kind == "telegram":
        palette_path = os.path.expanduser("~/.config/theme/Kitty.palette")
        if os.path.exists(palette_path):
            subprocess.run(["open", palette_path], check=False)


if __name__ == "__main__":
    main()
