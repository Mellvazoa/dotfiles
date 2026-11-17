#!/usr/bin/env python3
"""Fast Alt+Space float toggle for yabai (direct UNIX socket)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from smart_balance import adjust_windows, q, y
import smart_zoom

GRID = "10:10:1:1:8:8"


def main():
    win = q("--windows", "--window")
    if not win:
        return

    wid = win["id"]
    space = win.get("space", 1)

    state = smart_zoom.load(space)
    if state and state.get("zoomed_id") == wid:
        smart_zoom.unzoom(space, state)
        win = q("--windows", "--window", wid) or win

    if win.get("is-floating"):
        # Float -> Tile into layout and fit all windows cleanly
        y("window", wid, "--toggle", "float")
        y("window", wid, "--sub-layer", "normal")
        y("space", "--balance")
        adjust_windows(space, equalize_scalable=True)
    else:
        # Tile -> Float and center, then rebalance remaining tiled windows
        y("window", wid, "--toggle", "float")
        y("window", wid, "--grid", GRID)
        y("window", wid, "--sub-layer", "above")
        y("space", "--balance")
        adjust_windows(space)


if __name__ == "__main__":
    main()
