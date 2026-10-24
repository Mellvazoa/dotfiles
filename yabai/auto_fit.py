#!/usr/bin/env python3
import json
import subprocess
import sys

def main():
    try:
        displays = json.loads(subprocess.check_output(["yabai", "-m", "query", "--displays"], stderr=subprocess.DEVNULL))
        if not displays:
            return
        disp = displays[0]["frame"]
        max_w = disp["w"]
        max_h = disp["h"]

        windows = json.loads(subprocess.check_output(["yabai", "-m", "query", "--windows"], stderr=subprocess.DEVNULL))
        visible_windows = [
            w for w in windows 
            if w.get("is-visible") and not w.get("is-minimized") and not w.get("is-floating") and w.get("space") == displays[0].get("spaces", [1])[0]
        ]

        for w in visible_windows:
            f = w["frame"]
            over_x = (f["x"] + f["w"]) - (max_w - 6)
            over_y = (f["y"] + f["h"]) - (max_h - 6)

            # If window exceeds right edge, resize predecessor to give it room
            if over_x > 2:
                # Find sibling to its left
                left_siblings = [s for s in visible_windows if s["frame"]["x"] < f["x"] and abs(s["frame"]["y"] - f["y"]) < 50]
                if left_siblings:
                    target = left_siblings[0]
                    adj = int(over_x) + 4
                    subprocess.run(["yabai", "-m", "window", str(target["id"]), "--resize", f"right:-{adj}:0"], stderr=subprocess.DEVNULL)

            # If window exceeds bottom edge, resize predecessor above it
            if over_y > 2:
                top_siblings = [s for s in visible_windows if s["frame"]["y"] < f["y"] and abs(s["frame"]["x"] - f["x"]) < 50]
                if top_siblings:
                    target = top_siblings[0]
                    adj = int(over_y) + 4
                    subprocess.run(["yabai", "-m", "window", str(target["id"]), "--resize", f"bottom:0:-{adj}"], stderr=subprocess.DEVNULL)
    except Exception as e:
        pass

if __name__ == "__main__":
    main()
