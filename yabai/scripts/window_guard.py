#!/usr/bin/env python3
"""window_created guard for yabai (direct UNIX socket, <15ms).

1. If a new window opens while another window on the same space is zoomed (Alt+F),
   the new window is immediately made floating and centered (Alt+Space style) so it
   never flies off-screen or breaks the zoom.
2. Otherwise, for normal tiled window creation, runs smart_balance.adjust_windows()
   immediately so wide siblings (e.g. Preview + Brave, IDE + Telegram) resize and
   eliminate any overlap cleanly without requiring manual Alt+B.
3. If a window still overflows the display edge after smart_balance (when two apps'
   hard macOS minimum widths exceed the display width), floats and centers it.

Called from yabai: window_created (env YABAI_WINDOW_ID is set).
"""
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from smart_balance import adjust_windows, q, y

GRID = "10:10:1:1:8:8"
MARGIN = 6  # tolerated overflow in px


def float_center(wid):
    info = q("--windows", "--window", wid)
    if not info:
        return
    if not info.get("is-floating"):
        y("window", wid, "--toggle", "float")
    y("window", wid, "--grid", GRID)
    y("window", wid, "--sub-layer", "above")


def is_space_zoomed(space, space_wins):
    state_file = f"/tmp/yabai_zoom_space_{space}.json"
    if os.path.exists(state_file):
        try:
            with open(state_file) as f:
                st = json.load(f)
            zid = st.get("zoomed_id")
            zinfo = next((w for w in space_wins if w["id"] == zid), None)
            if zinfo and zinfo.get("is-visible") and not zinfo.get("is-minimized"):
                return True
            # Stale zoom state (zoomed window was minimized or closed)
            os.remove(state_file)
        except Exception:
            pass
    return any(
        w.get("has-fullscreen-zoom")
        for w in space_wins
        if not w.get("is-minimized") and w.get("is-visible")
    )


def overflowing(space, disp):
    dx, dw = disp["x"], disp["w"]
    bad = []
    for w in q("--windows", "--space", space) or []:
        if w.get("is-floating") or not w.get("is-visible") or w.get("is-minimized"):
            continue
        if w.get("has-fullscreen-zoom"):
            continue
        f = w["frame"]
        if f["x"] + f["w"] > dx + dw + MARGIN or f["x"] < dx - MARGIN:
            bad.append(w)
    return bad


def main():
    wid = os.environ.get("YABAI_WINDOW_ID")
    info = q("--windows", "--window", wid) if wid else None
    if not info:
        return

    # Ignore non-standard / already floating dialog windows
    space = info["space"]
    space_wins = q("--windows", "--space", space) or []

    # Case 1: Space has an active zoomed window -> float and center the new window immediately
    if is_space_zoomed(space, space_wins) and not info.get("has-fullscreen-zoom"):
        float_center(info["id"])
        return

    if info.get("is-floating"):
        return

    # Case 2: Tiled window created -> let yabai insert it into the BSP tree, then
    # run smart_balance so siblings resize cleanly and eliminate any overlaps.
    time.sleep(0.04)
    adjust_windows(space)

    # Check if any window still overflows due to hard macOS minimum window widths
    disp = (q("--displays", "--display") or {}).get("frame")
    if not disp:
        return
    for w in overflowing(space, disp):
        float_center(w["id"])


if __name__ == "__main__":
    main()
