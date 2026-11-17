#!/usr/bin/env python3
"""Ultra-fast Hyprland-style Alt+F zoom for yabai + JankyBorders via UNIX socket.

Fixes:
1. No screenshot stretching: yabai `window_animation_duration` & `window_opacity_duration`
   are 0.0 globally, and commands go directly to `/tmp/yabai_$USER.socket` (~1ms).
2. No ghost borders or accidental click-through on hidden background windows:
   - Sets JankyBorders `inactive_color=0x00000000` while zoomed so inactive window
     borders completely disappear (and restores `0x22244127` on unzoom).
   - Raises the zoomed window to `sub-layer=above` and lowers background windows to
     `sub-layer=below` so clicking anywhere on the zoomed window can NEVER hit a
     hidden background window underneath.
3. Restores exact pre-zoom opacity and sub-layer on unzoom / focus change / destroy / minimize.
4. Minimized window handling: Minimized windows (yellow circle) never block other windows
   from zooming, and when un-minimized, windows cleanly rejoin layout without overlaps.

Modes: (none) toggle | --reset | --cleanup | --ensure-opacity | --deminimized
"""
import fcntl
import glob
import json
import os
import pwd
import re
import socket
import struct
import subprocess
import sys
import time

USER = os.environ.get("USER") or pwd.getpwuid(os.getuid()).pw_name
SOCK_PATH = f"/tmp/yabai_{USER}.socket"
STATE = "/tmp/yabai_zoom_space_{}.json"
LOCK = "/tmp/yabai_zoom.lock"
HIDDEN = 0.001

BORDERS_BIN = "/opt/homebrew/bin/borders"
BORDERS_INACTIVE_NORMAL = "inactive_color=0x22244127"
BORDERS_INACTIVE_HIDDEN = "inactive_color=0x00000000"


def y(*args):
    """Send a message directly to yabai's UNIX domain socket (~1ms)."""
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
            return ""
        return raw.decode("utf-8", errors="replace").strip()
    except OSError:
        r = subprocess.run(["yabai", "-m", *str_args], capture_output=True, text=True)
        return r.stdout.strip() if r.returncode == 0 else ""


def set_borders_hidden(hidden):
    """Toggle JankyBorders inactive border visibility non-blockingly."""
    arg = BORDERS_INACTIVE_HIDDEN if hidden else BORDERS_INACTIVE_NORMAL
    try:
        subprocess.Popen(
            [BORDERS_BIN, arg],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except OSError:
        pass


def q(*args):
    out = y("query", *args)
    try:
        return json.loads(out) if out else None
    except ValueError:
        return None


def fallback_opacity(app):
    if app == "Telegram":
        return 0.85
    if re.search(r"Brave|Chrome|Safari|Arc|Zen|Firefox|Vivaldi|Edge", app or ""):
        return 0.78
    return 1.0


def set_op(wid, op):
    y("window", wid, "--opacity", f"{op:.3f}")


def load(space):
    try:
        with open(STATE.format(space)) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def drop(space):
    try:
        os.remove(STATE.format(space))
    except OSError:
        pass


def restore_windows(state, space_wins=None):
    if space_wins is None:
        space_wins = q("--windows") or []
    alive = {w["id"]: w for w in space_wins if not w.get("is-minimized")}
    layers = state.get("sub_layer", {})
    for wid_str, op in state.get("opacity", {}).items():
        wid = int(wid_str)
        if wid in alive:
            set_op(wid, max(float(op), 0.2))
            default_layer = "above" if alive[wid].get("is-floating") else "normal"
            orig_layer = layers.get(wid_str, default_layer)
            y("window", wid, "--sub-layer", orig_layer if orig_layer in ("above", "below", "normal") else default_layer)


def heal_hidden(space, wins=None):
    """Safety net: guarantee no visible window on the space stays at ~0 opacity or stuck sub-layer."""
    if wins is None:
        wins = q("--windows", "--space", space) or []
    for w in wins:
        if w.get("is-minimized") or w.get("app") == "wallpaper_gallery":
            continue
        if w.get("opacity", 1.0) < 0.2:
            set_op(w["id"], fallback_opacity(w.get("app")))
        target_layer = "above" if w.get("is-floating") else "normal"
        if w.get("sub-layer") != target_layer:
            y("window", w["id"], "--sub-layer", target_layer)


def zoom(win, wins):
    space = win["space"]
    others = [
        w for w in wins
        if w["id"] != win["id"] and w.get("is-visible") and not w.get("is-minimized")
    ]
    own_op = win.get("opacity", 1.0)
    own_layer = win.get("sub-layer", "normal")
    state = {
        "zoomed_id": win["id"],
        "floating": bool(win.get("is-floating")),
        "frame": win["frame"] if win.get("is-floating") else None,
        "opacity": {str(w["id"]): w.get("opacity", 1.0) for w in others},
        "sub_layer": {str(w["id"]): w.get("sub-layer", "normal") for w in others},
        "own_opacity": own_op,
        "own_layer": own_layer,
    }
    with open(STATE.format(space), "w") as f:
        json.dump(state, f)

    # 1. Hide JankyBorders inactive borders immediately so they don't overlay the zoomed window
    set_borders_hidden(True)

    # 2. Hide background windows and push them to sub-layer=below so clicks never hit them
    for w in others:
        set_op(w["id"], HIDDEN)
        y("window", w["id"], "--sub-layer", "below")

    # 3. Keep zoomed window at sub-layer=normal (still above hidden `below` windows,
    #    while allowing launchers, dialogs, and floating windows to appear on top)
    y("window", win["id"], "--sub-layer", "normal")
    if win.get("is-floating"):
        y("window", win["id"], "--grid", "1:1:0:0:1:1")
    else:
        y("window", win["id"], "--toggle", "zoom-fullscreen")

    if own_op < 0.2:
        set_op(win["id"], fallback_opacity(win.get("app")))


def unzoom(space, state, only_restore=False, wins=None):
    zid = state.get("zoomed_id")
    own_op = max(float(state.get("own_opacity", 1.0)), 0.2)
    own_layer = state.get("own_layer", "normal")
    if not state.get("floating"):
        own_layer = "normal"

    if wins is None:
        wins = q("--windows", "--space", space) or []

    if not only_restore and zid:
        info = next((w for w in wins if w["id"] == zid), None)
        if info is None:
            info = q("--windows", "--window", zid)
        if info and not info.get("is-minimized"):
            if state.get("floating") and state.get("frame"):
                f = state["frame"]
                y("window", zid, "--move", f"abs:{int(f['x'])}:{int(f['y'])}")
                y("window", zid, "--resize", f"abs:{int(f['w'])}:{int(f['h'])}")
            elif info.get("has-fullscreen-zoom"):
                y("window", zid, "--toggle", "zoom-fullscreen")
            y("window", zid, "--sub-layer", own_layer)
            if info.get("opacity", 1.0) < 0.2:
                set_op(zid, own_op)

    restore_windows(state, wins)
    drop(space)
    heal_hidden(space)
    set_borders_hidden(False)


def cleanup_stale_zooms():
    any_active_on_current = False
    cur_space = (q("--spaces", "--space") or {}).get("index")
    for path in glob.glob(STATE.format("*")):
        m = re.search(r"space_(\d+)\.json$", path)
        sp = int(m.group(1)) if m else None
        state = load(sp) if sp else None
        if not state:
            continue
        info = q("--windows", "--window", state.get("zoomed_id"))
        # Window is gone if destroyed, minimized, or no longer visible
        gone = (not info) or info.get("is-minimized") or (not info.get("is-visible"))
        if gone:
            unzoom(sp, state, only_restore=True)
        elif sp == cur_space:
            any_active_on_current = True
    set_borders_hidden(any_active_on_current)


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else ""

    lock = open(LOCK, "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        return

    if mode in ("--reset", "--cleanup"):
        cleanup_stale_zooms()
        cur_space = (q("--spaces", "--space") or {}).get("index")
        if cur_space and not load(cur_space):
            heal_hidden(cur_space)
        try:
            from smart_balance import adjust_windows
            adjust_windows()
        except Exception:
            pass
        return

    if mode == "--deminimized":
        cleanup_stale_zooms()
        wid = os.environ.get("YABAI_WINDOW_ID")
        if wid:
            info = q("--windows", "--window", wid)
            if info:
                app = info.get("app", "")
                set_op(wid, fallback_opacity(app))
                layer = "above" if info.get("is-floating") else "normal"
                y("window", wid, "--sub-layer", layer)
        try:
            from smart_balance import adjust_windows
            adjust_windows()
        except Exception:
            pass
        return

    wins = q("--windows", "--space") or []
    win = next((w for w in wins if w.get("has-focus")), None)
    if not win:
        win = q("--windows", "--window")
    if not win:
        return

    space = win["space"]
    state = load(space)

    # Check if the saved zoom state belongs to an already minimized/closed window
    if state:
        zinfo = next((w for w in wins if w["id"] == state.get("zoomed_id")), None)
        if not zinfo or zinfo.get("is-minimized") or not zinfo.get("is-visible"):
            unzoom(space, state, only_restore=True, wins=wins)
            state = None

    if mode == "--ensure-opacity":
        if win.get("app") in ("choose", "wallpaper_gallery") or not win.get("has-ax-reference"):
            return
        if state and state.get("zoomed_id") != win["id"]:
            if win.get("is-floating"):
                return
            time.sleep(0.10)
            win = q("--windows", "--window") or win
            state = load(space)
            if win.get("is-floating") or not state or state.get("zoomed_id") == win["id"]:
                return
            unzoom(space, state)
        elif not state:
            heal_hidden(space, wins)
            set_borders_hidden(False)
        return

    if state or win.get("has-fullscreen-zoom"):
        unzoom(space, state or {"zoomed_id": win["id"], "opacity": {}}, wins=wins)
    else:
        zoom(win, wins)


if __name__ == "__main__":
    main()
