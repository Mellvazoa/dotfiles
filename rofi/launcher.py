#!/usr/bin/env python3
import os
import sys
import subprocess
import urllib.parse

# 1. Collect Applications
app_dirs = [
    "/Applications",
    "/System/Applications",
    "/System/Applications/Utilities",
    os.path.expanduser("~/Applications"),
]

app_map = {}
for d in app_dirs:
    if not os.path.exists(d):
        continue
    for item in os.listdir(d):
        if item.endswith(".app"):
            name = item[:-4]
            full_path = os.path.join(d, item)
            app_map[name] = ("app", full_path)
        elif os.path.isdir(os.path.join(d, item)) and not item.startswith("."):
            sub_d = os.path.join(d, item)
            for sub_item in os.listdir(sub_d):
                if sub_item.endswith(".app"):
                    name = sub_item[:-4]
                    app_map[name] = ("app", os.path.join(sub_d, sub_item))

# 2. Key User Directories
folder_map = {
    "Downloads": ("folder", os.path.expanduser("~/Downloads")),
    "Screenshots (screen)": ("folder", os.path.expanduser("~/screen")),
    "Documents": ("folder", os.path.expanduser("~/Documents")),
    "Home (~/)": ("folder", os.path.expanduser("~")),
    "Waybar Config": ("folder", os.path.expanduser("~/Documents/Antigravity/waybar")),
}

# 3. Nerd Font Icons
icon_rules = {
    "kitty": " ",
    "terminal": " ",
    "iterm": " ",
    "code": "󰨞 ",
    "antigravity": "󰨞 ",
    "telegram": "󰈹 ",
    "discord": "󰒱 ",
    "brave": "󰖟 ",
    "chrome": "󰖟 ",
    "safari": "󰖟 ",
    "firefox": "󰖟 ",
    "qutebrowser": "󰖟 ",
    "spotify": "󰝚 ",
    "music": "󰝚 ",
    "finder": "󰉋 ",
    "settings": "󰒓 ",
    "system preferences": "󰒓 ",
    "system settings": "󰒓 ",
    "calculator": "󰃬 ",
    "ghidra": "󰈸 ",
    "steam": "󰓓 ",
}

def get_icon(name, item_type):
    if item_type == "folder":
        return "󰉋 "
    lower = name.lower()
    for k, icon in icon_rules.items():
        if k in lower:
            return icon
    return "󱓞 "

entries = []
entry_lookup = {}
added_names = set()

# Priority apps at the top
priority = ["Brave Browser", "Telegram", "Antigravity IDE", "kitty", "Finder"]
for p in priority:
    for name, (item_type, path) in app_map.items():
        if p.lower() in name.lower() and name not in added_names:
            icon = get_icon(name, item_type)
            display_str = f"{icon} {name}"
            entries.append(display_str)
            entry_lookup[display_str] = (item_type, path)
            added_names.add(name)

# Remaining apps
for name in sorted(app_map.keys(), key=lambda s: s.lower()):
    if name in added_names:
        continue
    item_type, path = app_map[name]
    icon = get_icon(name, item_type)
    display_str = f"{icon} {name}"
    entries.append(display_str)
    entry_lookup[display_str] = (item_type, path)

# Folders
for name, (item_type, path) in folder_map.items():
    icon = get_icon(name, item_type)
    display_str = f"{icon} {name}"
    entries.append(display_str)
    entry_lookup[display_str] = (item_type, path)

input_data = "\n".join(entries)

# Dynamic styling matching wallpaper theme
theme_path = os.path.expanduser("~/.config/rofi/colors.json")
bg_color = "353058"
text_color = "e4d2fd"
if os.path.exists(theme_path):
    try:
        import json
        with open(theme_path, "r") as f:
            t = json.load(f)
            bg_color = t.get("bg", bg_color)
            text_color = t.get("accent_light", text_color)
    except Exception:
        pass

choose_cmd = [
    "/opt/homebrew/bin/choose",
    "-p", "Type to filter...",
    "-n", "12",
    "-w", "42",
    "-s", "16",
    "-f", "JetBrainsMono Nerd Font",
    "-b", bg_color,
    "-c", text_color,
    "-u",
    "-z",
    "-a",
]

proc = subprocess.Popen(choose_cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
selected, _ = proc.communicate(input=input_data)
selected = selected.strip()

if not selected:
    sys.exit(0)

if selected in entry_lookup:
    item_type, path = entry_lookup[selected]
    if item_type == "app":
        subprocess.run(["open", path])
    elif item_type == "folder":
        subprocess.run(["open", path])
else:
    if selected.startswith("http://") or selected.startswith("https://"):
        subprocess.run(["open", selected])
    else:
        res = subprocess.run(["open", "-a", selected])
        if res.returncode != 0:
            q = urllib.parse.quote(selected)
            subprocess.run(["open", f"https://www.google.com/search?q={q}"])
