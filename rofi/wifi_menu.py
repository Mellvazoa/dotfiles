#!/usr/bin/env python3
import os
import sys
import json
import subprocess
from choose_overlay import run_choose
import re

CONFIG_DIR = os.path.dirname(os.path.abspath(__file__))
SWIFT_SCANNER = os.path.join(CONFIG_DIR, "scan_wifi.swift")

def get_theme_colors():
    theme_path = os.path.expanduser("~/.config/rofi/colors.json")
    bg_color = "353058"
    text_color = "e4d2fd"
    if os.path.exists(theme_path):
        try:
            with open(theme_path, "r") as f:
                t = json.load(f)
                bg_color = t.get("bg", bg_color)
                text_color = t.get("accent_light", text_color)
        except Exception:
            pass
    return bg_color, text_color

def notify(title, message):
    try:
        cmd = f'display notification "{message}" with title "{title}"'
        subprocess.run(["osascript", "-e", cmd], stderr=subprocess.DEVNULL)
    except Exception:
        pass

def get_wifi_power(iface="en0"):
    try:
        out = subprocess.check_output(["networksetup", "-getairportpower", iface], text=True)
        return "On" in out
    except Exception:
        return True

def get_current_ssid(iface="en0"):
    try:
        out = subprocess.check_output(["ipconfig", "getsummary", iface], text=True)
        m = re.search(r'\bSSID\s*:\s*(.+)', out)
        if m:
            return m.group(1).strip()
    except Exception:
        pass
    return None

def get_preferred_networks(iface="en0"):
    try:
        out = subprocess.check_output(["networksetup", "-listpreferredwirelessnetworks", iface], text=True)
        lines = [line.strip() for line in out.splitlines()[1:] if line.strip()]
        return set(lines)
    except Exception:
        return set()

def scan_networks():
    if not os.path.exists(SWIFT_SCANNER):
        return []
    try:
        out = subprocess.check_output(["/usr/bin/swift", SWIFT_SCANNER], text=True, stderr=subprocess.DEVNULL)
        nets = []
        for line in out.strip().splitlines():
            parts = line.split("\t")
            if len(parts) >= 3:
                ssid = parts[0].strip()
                rssi = int(parts[1]) if parts[1].lstrip("-").isdigit() else -70
                sec = parts[2].strip()
                nets.append({"ssid": ssid, "rssi": rssi, "security": sec})
        return nets
    except Exception:
        return []

def signal_icon(rssi):
    if rssi >= -55:
        return "󰤨 "
    elif rssi >= -65:
        return "󰤥 "
    elif rssi >= -75:
        return "󰤢 "
    else:
        return "󰤟 "

def prompt_password(ssid):
    # Try AppleScript secure dialog first for masked password entry
    as_script = f'''
    tell application "System Events"
        activate
        set res to display dialog "Enter password for \\"{ssid}\\":" default answer "" with hidden answer buttons {{"Cancel", "Connect"}} default button "Connect"
        return text returned of res
    end tell
    '''
    try:
        res = subprocess.check_output(["osascript", "-e", as_script], text=True, stderr=subprocess.DEVNULL)
        pwd = res.strip()
        if pwd:
            return pwd
    except Exception:
        pass

    # Fallback to choose
    bg, fg = get_theme_colors()
    choose_cmd = [
        "/opt/homebrew/bin/choose",
        "-p", f"Password for {ssid}:",
        "-n", "1",
        "-w", "42",
        "-s", "16",
        "-f", "JetBrainsMono Nerd Font",
        "-b", bg,
        "-c", fg,
        "-m",
        "-e",
    ]
    try:
        proc = subprocess.Popen(choose_cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        out, _ = proc.communicate(input="")
        return out.strip() if out else None
    except Exception:
        return None

def main():
    iface = "en0"
    is_on = get_wifi_power(iface)

    current_ssid = get_current_ssid(iface) if is_on else None
    saved_networks = get_preferred_networks(iface)

    entries = []
    item_map = {}

    if not is_on:
        label = "󰖩  Turn Wi-Fi On"
        entries.append(label)
        item_map[label] = ("action", "power_on")
    else:
        # Actions at top
        off_label = "󰖪  Turn Wi-Fi Off"
        entries.append(off_label)
        item_map[off_label] = ("action", "power_off")

        rescan_label = "󰑐  Rescan Networks"
        entries.append(rescan_label)
        item_map[rescan_label] = ("action", "rescan")

        # Scanned nearby networks
        scanned = scan_networks()
        scanned_ssids = set()

        # If current connected SSID is known, put it right under actions
        if current_ssid:
            icon = "󰤨 "
            display = f"{icon} {current_ssid}  ✓ Connected"
            entries.append(display)
            item_map[display] = ("ssid", current_ssid)
            scanned_ssids.add(current_ssid)

        for net in scanned:
            ssid = net["ssid"]
            if ssid in scanned_ssids:
                continue
            scanned_ssids.add(ssid)
            icon = signal_icon(net["rssi"])
            tag = "[Saved]" if ssid in saved_networks else f"[{net['security']}]"
            display = f"{icon} {ssid:<24} {net['rssi']} dBm  {tag}"
            entries.append(display)
            item_map[display] = ("ssid", ssid)

        # Also add any saved networks not seen in scan
        for s in sorted(saved_networks):
            if s not in scanned_ssids:
                display = f"󰤟  {s:<24}  [Saved / Out of range]"
                entries.append(display)
                item_map[display] = ("ssid", s)

    input_data = "\n".join(entries)
    bg, fg = get_theme_colors()

    choose_cmd = [
        "/opt/homebrew/bin/choose",
        "-p", "Select Wi-Fi Network...",
        "-n", "12",
        "-w", "48",
        "-s", "15",
        "-f", "JetBrainsMono Nerd Font",
        "-b", bg,
        "-c", fg,
        "-u",
        "-z",
        "-a",
    ]

    selected = run_choose(choose_cmd, input_data)

    if not selected or selected not in item_map:
        sys.exit(0)

    kind, target = item_map[selected]

    if kind == "action":
        if target == "power_on":
            subprocess.run(["networksetup", "-setairportpower", iface, "on"])
            notify("Wi-Fi", "Wi-Fi turned ON")
            subprocess.run(["sketchybar", "--trigger", "wifi_change"], stderr=subprocess.DEVNULL)
        elif target == "power_off":
            subprocess.run(["networksetup", "-setairportpower", iface, "off"])
            notify("Wi-Fi", "Wi-Fi turned OFF")
            subprocess.run(["sketchybar", "--trigger", "wifi_change"], stderr=subprocess.DEVNULL)
        elif target == "rescan":
            os.execv(sys.executable, [sys.executable] + sys.argv)
    elif kind == "ssid":
        if target == current_ssid:
            notify("Wi-Fi", f"Already connected to {target}")
            sys.exit(0)

        notify("Wi-Fi", f"Connecting to {target}...")
        
        # Try connecting without password first (works if in Keychain/preferred)
        res = subprocess.run(["networksetup", "-setairportnetwork", iface, target], capture_output=True, text=True)
        if res.returncode == 0:
            notify("Wi-Fi", f"Connected to {target}!")
            subprocess.run(["sketchybar", "--trigger", "wifi_change"], stderr=subprocess.DEVNULL)
            sys.exit(0)

        # If failed, prompt for password
        pwd = prompt_password(target)
        if not pwd:
            notify("Wi-Fi", "Connection cancelled")
            sys.exit(0)

        res2 = subprocess.run(["networksetup", "-setairportnetwork", iface, target, pwd], capture_output=True, text=True)
        if res2.returncode == 0:
            notify("Wi-Fi", f"Successfully connected to {target}!")
            subprocess.run(["sketchybar", "--trigger", "wifi_change"], stderr=subprocess.DEVNULL)
        else:
            err_msg = res2.stderr.strip() or res2.stdout.strip() or "Failed to join network"
            notify("Wi-Fi Error", f"{target}: {err_msg}")

if __name__ == "__main__":
    main()

