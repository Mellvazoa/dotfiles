#!/usr/bin/env python3
"""Quick window opacity menu (yabai) styled via choose + rofi/colors.json."""
import json
import os
import subprocess
import sys
from choose_overlay import _y, run_choose

OPACITY_STEPS = [1.00, 0.90, 0.85, 0.80, 0.75, 0.70, 0.60, 0.50, 0.35]


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


def get_focused_window():
    raw = _y("query", "--windows", "--window")
    if not raw:
        return None
    try:
        return json.loads(raw)
    except ValueError:
        return None


def main():
    win = get_focused_window()
    wid = win.get("id") if win else None
    app = win.get("app", "Window") if win else "Active Window"
    cur_op = float(win.get("opacity", 1.0)) if win else 1.0
    cur_pct = round(cur_op * 100)

    entries = []
    item_map = {}

    for val in OPACITY_STEPS:
        pct = round(val * 100)
        is_cur = win is not None and abs(cur_op - val) < 0.025
        mark = "●" if is_cur else "○"
        hint = " (opaque)" if pct == 100 else ""
        suffix = "  [current]" if is_cur else ""
        line = f"{mark}  {pct:>3d}%  {app}{hint}{suffix}"
        entries.append(line)
        item_map[line] = ("win_opacity", val)

    dim_line = "󰖲  Focus Dim · Active 100% / Inactive 85%"
    entries.append(dim_line)
    item_map[dim_line] = ("focus_dim", None)

    reset_line = "󰖳  Reset Opacity · Reapply yabairc Rules"
    entries.append(reset_line)
    item_map[reset_line] = ("reset_rules", None)

    bg, fg = get_theme_colors()
    choose_cmd = [
        "/opt/homebrew/bin/choose",
        "-p", f"Opacity · {app} ({cur_pct}%)...",
        "-n", "11",
        "-w", "48",
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
    if kind == "win_opacity" and target is not None:
        if wid is not None:
            _y("window", wid, "--opacity", f"{target:.2f}")
        else:
            subprocess.run(["yabai", "-m", "window", "--opacity", f"{target:.2f}"], check=False)
    elif kind == "focus_dim":
        _y("config", "active_window_opacity", "1.0")
        _y("config", "normal_window_opacity", "0.85")
    elif kind == "reset_rules":
        _y("config", "active_window_opacity", "1.0")
        _y("config", "normal_window_opacity", "1.0")
        subprocess.run(["yabai", "-m", "rule", "--apply"], check=False)


if __name__ == "__main__":
    main()
