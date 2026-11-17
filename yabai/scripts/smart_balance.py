#!/usr/bin/env python3
"""Smart window balancing (Alt+B) and overflow/overlap prevention for yabai.

Balancing rules:
1. Two scalable/flexible windows (e.g. IDE + kitty, Browser + Terminal, IDE + Browser)
   always split evenly 50/50 (handled by `yabai -m space --balance`).
2. Constrained / fixed-minimum-width apps (Telegram, Discord, Preview/Просмотр, Skim,
   PDF Expert) shrink or expand to their optimal minimum width (`min_w`), and the
   scalable sibling automatically adjusts to take the remaining width (`total_w - min_w`).
3. Overlap prevention: If an app on the left has a hard minimum width greater than its
   split allocation (e.g. Preview on the left needing 854px), any overlap between it
   and its right neighbor is automatically eliminated by shifting the vertical split.
4. Overflow prevention: If any window still overflows the right or bottom screen edge,
   the scalable neighbor is shrunk to fit both strictly inside the display bounds.
"""
import json
import os
import pwd
import socket
import struct
import subprocess
import sys

USER = os.environ.get("USER") or pwd.getpwuid(os.getuid()).pw_name
SOCK_PATH = f"/tmp/yabai_{USER}.socket"

# Constrained apps: these cannot or should not be arbitrarily stretched/shrunk to 50%,
# so they take their target `min_w` and the scalable neighbor takes the rest.
# All other apps are treated as `scalable` and split 50/50 with each other!
CONSTRAINED_MIN_WIDTH = {
    # Compact messengers (shrink to their minimum width so IDEs/browsers get more room)
    "Telegram":   560,
    "Discord":    620,
    # Document/PDF viewers (need >50% width to display pages comfortably)
    "Preview":    860,
    "Просмотр":   860,
    "Skim":       860,
    "PDF Expert": 860,
}

# Minimum safe width for any scalable app when yielding space to a constrained app
SCALABLE_FLOOR_W = 380


def y(*args):
    """Send a message directly to yabai's UNIX domain socket (~1ms). Returns (ok, output)."""
    str_args = [str(a) for a in args]
    try:
        payload = ("\x00".join(str_args) + "\x00\x00").encode("utf-8")
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.settimeout(0.5)
            s.connect(SOCK_PATH)
            s.sendall(struct.pack("<I", len(payload)) + payload)
            s.shutdown(socket.SHUT_WR)
            chunks = []
            while True:
                chunk = s.recv(65536)
                if not chunk:
                    break
                chunks.append(chunk)
        raw = b"".join(chunks)
        if raw.startswith(b"\x07"):
            return False, raw[1:].decode("utf-8", errors="replace").strip()
        return True, raw.decode("utf-8", errors="replace").strip()
    except OSError:
        r = subprocess.run(["yabai", "-m", *str_args], capture_output=True, text=True)
        return (r.returncode == 0), (r.stdout.strip() if r.returncode == 0 else r.stderr.strip())


def q(*args):
    ok, out = y("query", *args)
    if not ok or not out:
        return None
    try:
        return json.loads(out)
    except ValueError:
        return None


def get_constrained_min_w(app_name):
    """Returns target min_w if app is constrained, or None if app is freely scalable (50/50)."""
    if not app_name:
        return None
    for k, min_w in CONSTRAINED_MIN_WIDTH.items():
        if k.lower() == app_name.lower() or k.lower() in app_name.lower():
            return min_w
    return None


def restore_opacities_and_layers(windows):
    """Guarantees no tiled window remains stuck at 0.001 opacity or wrong sub-layer."""
    for w in windows:
        if w.get("is-minimized") or w.get("app") in ("wallpaper_gallery", "tg_music"):
            continue
        wid = w.get("id")
        op = w.get("opacity", 1.0)
        if op < 0.2:
            app = w.get("app", "")
            if app == "Telegram":
                target_op = "0.85"
            elif any(b in app for b in ["Brave", "Chrome", "Safari", "Arc", "Zen", "Firefox", "Vivaldi", "Edge"]):
                target_op = "0.78"
            else:
                target_op = "1.0"
            y("window", wid, "--opacity", target_op)
        if not w.get("is-floating") and w.get("sub-layer") != "normal":
            y("window", wid, "--sub-layer", "normal")


def find_horizontal_pairs(visible_windows):
    """Finds horizontally adjacent window pairs (Window A on left, Window B on right)."""
    if len(visible_windows) < 2:
        return []

    sorted_wins = sorted(visible_windows, key=lambda w: w["frame"]["x"])
    pairs = []

    for i in range(len(sorted_wins)):
        a = sorted_wins[i]
        fa = a["frame"]
        for j in range(i + 1, len(sorted_wins)):
            b = sorted_wins[j]
            fb = b["frame"]

            # Must overlap vertically significantly
            v_overlap = min(fa["y"] + fa["h"], fb["y"] + fb["h"]) - max(fa["y"], fb["y"])
            min_h = min(fa["h"], fb["h"])
            if min_h <= 0 or (v_overlap / min_h) <= 0.4:
                continue

            # Ensure no intermediate window between A and B horizontally
            in_between = any(
                c["id"] not in (a["id"], b["id"])
                and fa["x"] < c["frame"]["x"] < fb["x"]
                and (min(fa["y"] + fa["h"], c["frame"]["y"] + c["frame"]["h"]) - max(fa["y"], c["frame"]["y"])) > 50
                for c in sorted_wins
            )
            if in_between:
                continue

            pairs.append((a, b))
            break  # A pairs only with its immediate right neighbor

    return pairs


def adjust_horizontal_overlap(visible_windows):
    """
    Detects and immediately fixes any horizontal overlap between adjacent windows
    (e.g. when Preview is on the left with min width 854px and overlaps Brave).
    """
    pairs = find_horizontal_pairs(visible_windows)
    for a, b in pairs:
        fa = a["frame"]
        fb = b["frame"]
        overlap = (fa["x"] + fa["w"]) - fb["x"]
        if overlap > 2:
            adj = int(overlap) + 4
            ok, _ = y("window", a["id"], "--resize", f"right:{adj}:0")
            if not ok:
                y("window", b["id"], "--resize", f"left:{adj}:0")


def smart_horizontal_balance(visible_windows, disp_frame, EqualizeScalable=False):
    """
    - If both windows in a horizontal pair are scalable: split evenly 50/50.
    - If one window is constrained (e.g. Telegram, Discord, Preview/Просмотр) and the
      other is scalable: set the constrained window to its minimum width (`min_w`) and
      fit the scalable window to `total_w - min_w`.
    """
    pairs = find_horizontal_pairs(visible_windows)
    if not pairs:
        return

    usable_right = disp_frame["x"] + disp_frame["w"] - 2

    for a, b in pairs:
        fa = a["frame"]
        fb = b["frame"]
        right_edge = min(fb["x"] + fb["w"], usable_right)
        total_w = right_edge - fa["x"] - 4  # 4px gap
        if total_w < 500:
            continue

        min_a = get_constrained_min_w(a.get("app"))
        min_b = get_constrained_min_w(b.get("app"))

        # Actual split width allocated to Window A
        alloc_w_a = (fb["x"] - fa["x"] - 4) if fb["x"] > fa["x"] else fa["w"]

        # Detect if either window has a hard macOS minimum width causing screen overflow
        overflowing_right = (fb["x"] + fb["w"]) > (usable_right + 2)
        if overflowing_right and min_b is None:
            min_b = fb["w"]

        if min_a is None and min_b is None:
            # Both windows are freely scalable -> 50/50 split
            if not EqualizeScalable:
                continue
            target_w_a = total_w * 0.50
        elif min_a is not None and min_b is None:
            # A is constrained (e.g. Preview or Telegram on the left), B is scalable
            eff_min_a = max(min_a, fa["w"])
            target_w_a = min(eff_min_a, total_w - SCALABLE_FLOOR_W)
        elif min_a is None and min_b is not None:
            # A is scalable, B is constrained (e.g. Telegram or Preview on the right)
            eff_min_b = max(min_b, fb["w"]) if overflowing_right else min_b
            target_w_a = max(SCALABLE_FLOOR_W, total_w - eff_min_b)
        else:
            # Both A and B are constrained -> allocate proportionally to their minimums
            target_w_a = total_w * (min_a / (min_a + min_b))

        delta = target_w_a - alloc_w_a
        if abs(delta) > 8:
            adj = int(round(delta))
            ok, _ = y("window", a["id"], "--resize", f"right:{adj}:0")
            if not ok:
                y("window", b["id"], "--resize", f"left:{-adj}:0")


def adjust_horizontal_overflow(visible_windows, disp_frame):
    """Pulls any tiled window overflowing the right edge of the display back inside."""
    usable_right = disp_frame["x"] + disp_frame["w"] - 2
    for w in visible_windows:
        f = w["frame"]
        over_x = (f["x"] + f["w"]) - usable_right
        if over_x > 4:
            left_siblings = [
                s for s in visible_windows
                if s["id"] != w["id"]
                and s["frame"]["x"] < f["x"]
                and (min(f["y"] + f["h"], s["frame"]["y"] + s["frame"]["h"]) - max(f["y"], s["frame"]["y"]) > 80)
            ]
            adj = int(over_x) + 4
            if left_siblings:
                target = max(left_siblings, key=lambda s: s["frame"]["x"])
                ok, _ = y("window", target["id"], "--resize", f"right:-{adj}:0")
                if not ok:
                    y("window", w["id"], "--resize", f"left:-{adj}:0")
            else:
                y("window", w["id"], "--resize", f"left:-{adj}:0")


def adjust_vertical_windows(visible_windows, usable_bottom):
    """Ensures windows do not exceed the bottom of the screen."""
    try:
        telegram_win = next((w for w in visible_windows if w.get("app") == "Telegram"), None)
        if telegram_win:
            t_frame = telegram_win["frame"]
            t_id = telegram_win["id"]

            col_siblings = [
                w for w in visible_windows
                if w["id"] != t_id and (min(t_frame["x"] + t_frame["w"], w["frame"]["x"] + w["frame"]["w"]) - max(t_frame["x"], w["frame"]["x"]) > 100)
            ]

            if col_siblings:
                above = [w for w in col_siblings if w["frame"]["y"] < t_frame["y"]]
                below = [w for w in col_siblings if w["frame"]["y"] > t_frame["y"]]

                if above and not below:
                    closest_above = max(above, key=lambda w: w["frame"]["y"])
                    bottom_edge = t_frame["y"] + t_frame["h"]
                    over_y = bottom_edge - usable_bottom
                    if over_y > 2:
                        adj = int(over_y) + 4
                        y("window", closest_above["id"], "--resize", f"bottom:0:-{adj}")
                        return

                if below and not above:
                    closest_below = min(below, key=lambda w: w["frame"]["y"])
                    t_bottom = t_frame["y"] + t_frame["h"]
                    below_y = closest_below["frame"]["y"]
                    overlap = t_bottom - below_y
                    if overlap > 0:
                        adj = int(overlap) + 4
                        y("window", t_id, "--resize", f"bottom:0:{adj}")
                        return
                    else:
                        below_bottom = closest_below["frame"]["y"] + closest_below["frame"]["h"]
                        over_y = below_bottom - usable_bottom
                        if over_y > 2:
                            adj = int(over_y) + 2
                            y("window", closest_below["id"], "--resize", f"bottom:0:-{adj}")
                            return

        for w in visible_windows:
            f = w["frame"]
            bottom_edge = f["y"] + f["h"]
            over_y = bottom_edge - usable_bottom
            if over_y > 6:
                top_siblings = [
                    s for s in visible_windows
                    if s["frame"]["y"] < f["y"] and (min(f["x"] + f["w"], s["frame"]["x"] + s["frame"]["w"]) - max(f["x"], s["frame"]["x"]) > 100)
                ]
                if top_siblings:
                    target = max(top_siblings, key=lambda s: s["frame"]["y"])
                    adj = int(over_y) + 2
                    y("window", target["id"], "--resize", f"bottom:0:-{adj}")
    except Exception:
        pass


def adjust_windows(space_idx=None, equalize_scalable=False):
    try:
        if space_idx is None:
            space = q("--spaces", "--space") or {}
            space_idx = space.get("index", 1)

        display = q("--displays", "--display") or {}
        disp_frame = display.get("frame", {"x": 0, "y": 0, "w": 1470, "h": 956})
        usable_bottom = disp_frame["y"] + disp_frame["h"] - 8

        windows = q("--windows", "--space", space_idx) or []

        # 1. Restore opacities and normal sub-layer unless space is currently zoomed
        if not os.path.exists(f"/tmp/yabai_zoom_space_{space_idx}.json"):
            restore_opacities_and_layers(windows)

        visible_windows = [
            w for w in windows
            if w.get("is-visible") and not w.get("is-minimized") and not w.get("is-floating") and not w.get("has-fullscreen-zoom")
        ]

        # 2. Smart horizontal balance (50/50 for scalable pairs; min_w for constrained + rest for scalable)
        smart_horizontal_balance(visible_windows, disp_frame, EqualizeScalable=equalize_scalable)

        # 3. Horizontal overlap resolution (e.g. Preview on left overlapping Brave on right)
        windows_overlap = q("--windows", "--space", space_idx) or []
        visible_overlap = [
            w for w in windows_overlap
            if w.get("is-visible") and not w.get("is-minimized") and not w.get("is-floating") and not w.get("has-fullscreen-zoom")
        ]
        adjust_horizontal_overlap(visible_overlap)

        # 4. Horizontal right-edge & vertical bottom-edge overflow prevention
        windows_after = q("--windows", "--space", space_idx) or []
        visible_after = [
            w for w in windows_after
            if w.get("is-visible") and not w.get("is-minimized") and not w.get("is-floating") and not w.get("has-fullscreen-zoom")
        ]
        adjust_horizontal_overflow(visible_after, disp_frame)
        adjust_vertical_windows(visible_after, usable_bottom)

    except Exception:
        pass


def balance():
    # 1. Equalize all BSP splits 50/50 first
    y("space", "--balance")
    # 2. Adjust pairs containing constrained apps and eliminate any overlap/overflow
    adjust_windows(equalize_scalable=True)


if __name__ == "__main__":
    balance()
